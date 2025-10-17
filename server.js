/**
 * CoreGeek Displays Signage Player
 * Fetches public event feeds and renders them for Raspberry Pi kiosk displays
 * 
 * Architecture references:
 * - Section 8.4: Event fetch and server implementation
 * - Section 8.5: Runtime configuration via environment variables
 * - Section 8.8: Caching, offline fallback, and health monitoring
 */

import express from 'express';
import fetch from 'node-fetch';
import nunjucks from 'nunjucks';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// ============================================================================
// Configuration (Section 8.5)
// ============================================================================

const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  controllerBaseUrl: process.env.CONTROLLER_BASE_URL || 'https://displays.example.com',
  controllerApiKey: process.env.CONTROLLER_API_KEY || null,
  venueSlug: process.env.VENUE_SLUG || null,
  fetchIntervalS: parseInt(process.env.FETCH_INTERVAL_S || '60', 10),
  displayRotationS: parseInt(process.env.DISPLAY_ROTATION_S || '10', 10),
  maxEventsDisplay: parseInt(process.env.MAX_EVENTS_DISPLAY || '6', 10),
  offlineRetentionHours: parseInt(process.env.OFFLINE_RETENTION_HOURS || '24', 10),
};

function sanitizeUrlTrailingSlash(urlString) {
  return urlString.replace(/\/+$/, '');
}

function coerceInteger(value, fallback, label, minimum = 1) {
  const numeric = Number.isFinite(value) ? Math.floor(value) : Number.NaN;

  if (!Number.isFinite(numeric) || numeric < minimum) {
    console.warn(`⚠ Invalid ${label} value '${value}'. Falling back to ${fallback}.`);
    return fallback;
  }

  return numeric;
}

function validateConfiguration() {
  const rawBaseUrl = (config.controllerBaseUrl || '').trim();

  if (!rawBaseUrl || rawBaseUrl === 'https://displays.example.com') {
    console.error('✗ CONTROLLER_BASE_URL must be configured. Update /opt/signage/.env or set the environment variable.');
    process.exit(1);
  }

  let parsedBaseUrl;
  try {
    parsedBaseUrl = new URL(rawBaseUrl);
  } catch (err) {
    console.error(`✗ CONTROLLER_BASE_URL is invalid: ${err.message}`);
    process.exit(1);
  }

  if (!['http:', 'https:'].includes(parsedBaseUrl.protocol)) {
    console.error('✗ CONTROLLER_BASE_URL must use http or https.');
    process.exit(1);
  }

  config.controllerBaseUrl = sanitizeUrlTrailingSlash(parsedBaseUrl.toString());
  if (typeof config.controllerApiKey === 'string') {
    const trimmedKey = config.controllerApiKey.trim();
    config.controllerApiKey = trimmedKey.length > 0 ? trimmedKey : null;
  }

  config.fetchIntervalS = coerceInteger(config.fetchIntervalS, 60, 'FETCH_INTERVAL_S', 15);
  config.displayRotationS = coerceInteger(config.displayRotationS, 10, 'DISPLAY_ROTATION_S', 5);
  config.maxEventsDisplay = coerceInteger(config.maxEventsDisplay, 6, 'MAX_EVENTS_DISPLAY', 1);
  config.offlineRetentionHours = coerceInteger(config.offlineRetentionHours, 24, 'OFFLINE_RETENTION_HOURS', 1);
  config.port = coerceInteger(config.port, 3000, 'PORT', 1);
}

validateConfiguration();

// ============================================================================
// Data Cache & State Management (Section 8.8)
// ============================================================================

let cachedDataset = {
  events: [],
  venue: null,
  fetchedAt: null,
  lastSuccessfulFetch: null,
  isOffline: false,
  errorCount: 0,
};

/**
 * Hydrate media URLs to fully-qualified paths (Section 5.3)
 * Converts relative /uploads/* paths to absolute URLs
 */
function hydrateMediaUrls(events) {
  return events.map(event => {
    if (event.imageUrl && event.imageUrl.startsWith('/uploads/')) {
      return {
        ...event,
        imageUrl: `${config.controllerBaseUrl}${event.imageUrl}`,
      };
    }
    return event;
  });
}

/**
 * Sort events by start datetime, showing upcoming events first
 */
function sortEventsByTime(events) {
  return [...events].sort((a, b) => {
    const dateA = new Date(a.startDatetime);
    const dateB = new Date(b.startDatetime);
    return dateA - dateB;
  });
}

/**
 * Check if cached data is still valid for offline fallback (Section 8.8)
 */
function isCacheValid() {
  if (!cachedDataset.lastSuccessfulFetch) return false;
  
  const cacheAgeMs = Date.now() - new Date(cachedDataset.lastSuccessfulFetch).getTime();
  const maxAgeMs = config.offlineRetentionHours * 60 * 60 * 1000;
  
  return cacheAgeMs < maxAgeMs;
}

/**
 * Periodic event refresh (Section 8.4)
 * Fetches from public API endpoints and maintains offline fallback
 */
async function refreshEvents() {
  const fetchTimestamp = new Date().toISOString();
  console.log(`[${fetchTimestamp}] Fetching events...`);

  try {
    // Determine endpoint based on venue configuration (Section 4)
    const endpoint = config.venueSlug
      ? `${config.controllerBaseUrl}/api/public/venues/${config.venueSlug}/events`
      : `${config.controllerBaseUrl}/api/public/events`;

    console.log(`  → Endpoint: ${endpoint}`);

    const headers = {
      'Accept': 'application/json',
      'User-Agent': 'CoreGeek-Signage-Player/1.0',
    };

    if (config.controllerApiKey) {
      headers['x-api-key'] = config.controllerApiKey;
    }

    const res = await fetch(endpoint, {
      headers,
      timeout: 10000, // 10 second timeout
    });

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${res.statusText}`);
    }

    let events = await res.json();
    
    // Hydrate media URLs (Section 5.3)
    events = hydrateMediaUrls(events);
    
    // Sort by start time
    events = sortEventsByTime(events);

    // Optionally fetch venue metadata if venue slug is configured
    let venue = null;
    if (config.venueSlug) {
      try {
        const venueHeaders = {
          'Accept': 'application/json',
        };

        if (config.controllerApiKey) {
          venueHeaders['x-api-key'] = config.controllerApiKey;
        }

        const venueRes = await fetch(
          `${config.controllerBaseUrl}/api/public/venues/${config.venueSlug}`,
          { headers: venueHeaders, timeout: 5000 }
        );
        if (venueRes.ok) {
          venue = await venueRes.json();
        }
      } catch (err) {
        console.warn('  ⚠ Venue metadata fetch failed:', err.message);
      }
    }

    // Update cache with successful fetch
    cachedDataset = {
      events,
      venue,
      fetchedAt: fetchTimestamp,
      lastSuccessfulFetch: fetchTimestamp,
      isOffline: false,
      errorCount: 0,
    };

    console.log(`  ✓ Fetched ${events.length} events successfully`);

  } catch (err) {
    cachedDataset.errorCount++;
    cachedDataset.fetchedAt = fetchTimestamp;
    
    // Maintain offline mode with last good data (Section 8.8)
    if (isCacheValid()) {
      cachedDataset.isOffline = true;
      console.error(`  ✗ Fetch failed (attempt ${cachedDataset.errorCount}), using cached data:`, err.message);
    } else {
      cachedDataset.isOffline = true;
      console.error(`  ✗ Fetch failed and cache expired:`, err.message);
    }
  }
}

// ============================================================================
// Express Application Setup
// ============================================================================

const app = express();

// Configure Nunjucks template engine
nunjucks.configure(join(__dirname, 'views'), {
  autoescape: true,
  express: app,
  noCache: process.env.NODE_ENV !== 'production',
});

app.set('view engine', 'njk');

// Serve static assets (CSS, fonts, etc.)
app.use('/static', express.static(join(__dirname, 'public')));

// ============================================================================
// Routes
// ============================================================================

/**
 * Main signage display route
 * Renders events with metadata for Chromium kiosk (Section 8.7)
 */
app.get('/', (_req, res) => {
  // Limit displayed events
  const displayEvents = cachedDataset.events.slice(0, config.maxEventsDisplay);
  
  res.render('events.njk', {
    events: displayEvents,
    venue: cachedDataset.venue,
    fetchedAt: cachedDataset.fetchedAt,
    lastSuccessfulFetch: cachedDataset.lastSuccessfulFetch,
    isOffline: cachedDataset.isOffline,
    errorCount: cachedDataset.errorCount,
    config: {
      displayRotationS: config.displayRotationS,
      controllerBaseUrl: config.controllerBaseUrl,
    },
  });
});

/**
 * Health check endpoint (Section 8.8)
 * Used by platform health checks and monitoring systems
 */
app.get('/healthz', (_req, res) => {
  const isHealthy = isCacheValid() || cachedDataset.events.length > 0;
  
  if (isHealthy) {
    res.status(200).json({
      status: 'healthy',
      events: cachedDataset.events.length,
      lastFetch: cachedDataset.lastSuccessfulFetch,
      isOffline: cachedDataset.isOffline,
      cacheValid: isCacheValid(),
    });
  } else {
    res.status(503).json({
      status: 'unhealthy',
      error: 'No valid event data available',
      lastFetch: cachedDataset.lastSuccessfulFetch,
    });
  }
});

/**
 * Status page for debugging (accessible at /status)
 */
app.get('/status', (_req, res) => {
  res.json({
    ...cachedDataset,
    config,
    uptime: process.uptime(),
    memory: process.memoryUsage(),
  });
});

// ============================================================================
// Server Initialization
// ============================================================================

// Perform initial fetch immediately
await refreshEvents();

// Schedule periodic refreshes (Section 8.4)
const refreshIntervalMs = config.fetchIntervalS * 1000;
setInterval(refreshEvents, refreshIntervalMs);

console.log(`\n🚀 CoreGeek Signage Player Configuration:`);
console.log(`   Controller: ${config.controllerBaseUrl}`);
console.log(`   API Key: ${config.controllerApiKey ? 'provided' : 'not set (public endpoints)'}`);
console.log(`   Venue: ${config.venueSlug || '(all public events)'}`);
console.log(`   Fetch Interval: ${config.fetchIntervalS}s`);
console.log(`   Display Rotation: ${config.displayRotationS}s`);
console.log(`   Max Events Display: ${config.maxEventsDisplay}`);
console.log(`   Offline Retention: ${config.offlineRetentionHours}h\n`);

app.listen(config.port, () => {
  console.log(`✓ Signage server ready on http://localhost:${config.port}`);
  console.log(`✓ Health check available at http://localhost:${config.port}/healthz\n`);
});
