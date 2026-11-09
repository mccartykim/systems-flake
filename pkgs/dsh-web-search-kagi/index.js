/**
 * Kagi-backed `WebSearchProvider` plugin for DeepSeek Harness.
 *
 * The plugin is loaded by absolute path from a Cordis patch row (a Nix store
 * path in production), so it has no `node_modules` and imports nothing. It
 * registers one provider, `kagi`, with the `ctx.web` seam: `POST /search` with
 * `workflow: "search"` against Kagi's Search API v1, normalized to the seam's
 * `{ url, title, snippet, publishedAt }` source shape.
 *
 * @module dsh-web-search-kagi
 */

/** Stable plugin name used by loader diagnostics. */
export const name = 'web-search-kagi'

/** The web seam this provider registers into. */
export const inject = ['web']

/** Stable provider id this plugin registers under. */
export const KAGI_PROVIDER_ID = 'kagi'

/** Default Kagi Search API base; `/search` is appended. */
export const KAGI_DEFAULT_BASE_URL = 'https://kagi.com/api/v1'

/** Default credential reference; its value is resolved per search and never stored here. */
export const KAGI_DEFAULT_API_KEY_ENV = 'KAGI_API_KEY'

/** Attribution header sent on every request. */
const USER_AGENT = 'dsh-web-search-kagi/0.1.0'

/** Credential-reference grammar mirrored from `@deepseek-ai/dsh-credentials`. */
const CREDENTIAL_REF_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/

/**
 * A `WebError`-shaped failure.
 *
 * DSH's real class is `HarnessError`: an `Error` carrying a stable `code`.
 * A plugin loaded from a plain file cannot import it, so this reproduces the
 * same runtime shape: the tool pipeline reads `message`, and routing reads
 * `code` (`WEB_PROVIDER_ERROR`, `WEB_ABORTED`).
 */
export class WebError extends Error {
  /**
   * @param {string} message - human-readable failure description.
   * @param {string} code - stable machine-routable failure class.
   * @param {ErrorOptions} [options] - standard `cause` chaining.
   */
  constructor(message, code, options) {
    super(message, options)
    this.code = code
    this.name = 'WebError'
  }
}

/** True for a plain JSON object (not null, not an array). */
function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

/** First non-empty string among the candidates, or `undefined`. */
function firstString(...candidates) {
  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.length > 0) return candidate
  }
  return undefined
}

/** True when `value` is an absolute URL a source can cite. */
function isCitableUrl(value) {
  return typeof value === 'string' && URL.canParse(value)
}

/**
 * Find the HTML/web result array in a Kagi response.
 *
 * The documented v1 shape is `{ meta, data: { search: [...] } }`. The fall
 * backs accept a bare result array or a top-level `results` array so a proxy
 * or an older deployment cannot force the provider to drop every source.
 *
 * @param {unknown} payload - parsed response body.
 * @returns {unknown[]} the candidate result entries, or `[]`.
 */
function resultEntries(payload) {
  if (Array.isArray(payload)) return payload
  if (!isObject(payload)) return []
  if (Array.isArray(payload.data)) return payload.data
  if (isObject(payload.data) && Array.isArray(payload.data.search)) return payload.data.search
  if (Array.isArray(payload.results)) return payload.results
  return []
}

/**
 * Map one Kagi search result to a normalized source.
 *
 * `url` is required; `title`, `snippet`, and the publication time are
 * optional in the seam, so a missing one is omitted rather than invented.
 * A result without a citable URL is dropped — the seam's source shape cannot
 * represent it.
 *
 * @param {unknown} result - one entry of Kagi's `data.search[]`.
 * @returns {{ url: string, title?: string, snippet?: string, publishedAt?: string } | undefined}
 *   the normalized source, or `undefined` when the entry has no usable URL.
 */
export function mapKagiResult(result) {
  if (!isObject(result)) return undefined
  const url = firstString(result.url, result.turl, result.t)
  if (!isCitableUrl(url)) return undefined
  const title = firstString(result.title)
  const snippet = firstString(result.snippet)
  const publishedAt = firstString(result.time, result.publishedAt, result.publishedDate, result.published)
  return {
    url,
    ...title !== undefined ? { title } : {},
    ...snippet !== undefined ? { snippet } : {},
    ...publishedAt !== undefined ? { publishedAt } : {},
  }
}

/**
 * Map a Kagi response envelope to a normalized search result.
 *
 * Kagi returns no generated answer, so `content` is omitted. The web seam
 * owns the final `maxResults` truncation, so `truncated` is always `false`.
 * Duplicate URLs are collapsed (first occurrence wins).
 *
 * @param {unknown} payload - the parsed `POST /search` response body.
 * @returns {{ sources: Array<{ url: string, title?: string, snippet?: string, publishedAt?: string }>, truncated: boolean }}
 *   the normalized result.
 */
export function mapKagiResponse(payload) {
  const sources = []
  const seen = new Set()
  for (const entry of resultEntries(payload)) {
    const source = mapKagiResult(entry)
    if (source === undefined || seen.has(source.url)) continue
    seen.add(source.url)
    sources.push(source)
  }
  return { sources, truncated: false }
}

/**
 * Best-effort message from a Kagi error envelope.
 *
 * The documented non-2xx shape uses `error[]`, but live Kagi responses also use
 * the plural `errors[]` (observed for an invalid token, returned as HTTP 400
 * rather than 401), so both keys are read. The first non-empty message wins;
 * a bare string form and the top-level `message` are accepted as fallbacks.
 *
 * @param {unknown} payload - parsed error body.
 * @returns {string | undefined} the provider-supplied detail.
 */
export function kagiErrorMessage(payload) {
  if (!isObject(payload)) return undefined
  for (const key of ['errors', 'error']) {
    const value = payload[key]
    if (Array.isArray(value)) {
      for (const entry of value) {
        if (isObject(entry)) {
          const detail = firstString(entry.message)
          if (detail !== undefined) return detail
        }
      }
    }
    const bare = typeof value === 'string' ? firstString(value) : undefined
    if (bare !== undefined) return bare
  }
  return firstString(payload.message)
}

/** True for a base URL that can be requested (a cheap local config check). */
function isValidBaseUrl(baseURL) {
  return URL.canParse(baseURL)
}

/** True for a credential reference the credentials service accepts. */
function isValidApiKeyEnv(apiKeyEnv) {
  return CREDENTIAL_REF_PATTERN.test(apiKeyEnv)
}

/** True for a result limit that can be sent to Kagi (1..1024 whole number). */
function isValidLimit(value) {
  return Number.isInteger(value) && value >= 1 && value <= 1024
}

/** True for a fetch/`AbortSignal` abort, surfaced as `WEB_ABORTED`. */
function isAbortError(error) {
  return error instanceof DOMException && error.name === 'AbortError'
}

/** Build this provider's stable cancellation error while retaining the caller's reason. */
function searchAborted(signal, fallback) {
  return new WebError('Kagi search aborted', 'WEB_ABORTED', {
    cause: signal?.aborted === true ? signal.reason : fallback,
  })
}

/** Throw the provider's cancellation error when the caller already aborted. */
function throwIfAborted(signal) {
  if (signal?.aborted === true) throw searchAborted(signal)
}

/**
 * Race one asynchronous preflight against caller cancellation.
 * @template T
 * @param {Promise<T>} operation - the preflight to run.
 * @param {AbortSignal | undefined} signal - the search's cancellation signal.
 * @returns {Promise<T>} the operation's settlement, or rejection with `WEB_ABORTED`.
 */
function abortable(operation, signal) {
  if (signal === undefined) return operation
  if (signal.aborted) return Promise.reject(searchAborted(signal))
  return new Promise((resolve, reject) => {
    const onAbort = () => { reject(searchAborted(signal)) }
    signal.addEventListener('abort', onAbort, { once: true })
    void operation.then(
      (value) => {
        signal.removeEventListener('abort', onAbort)
        resolve(value)
      },
      (error) => {
        signal.removeEventListener('abort', onAbort)
        reject(error)
      },
    )
  })
}

/**
 * Resolved provider options supplied by the plugin's `apply`.
 *
 * @typedef {object} KagiSearchProviderOptions
 * @property {() => Promise<string | undefined>} resolveApiKey - resolve the current Kagi API key, per search.
 * @property {string} apiKeyEnv - credential reference named in missing-key diagnostics.
 * @property {string} baseURL - endpoint base; `/search` is appended.
 * @property {number | undefined} [maxResults] - default limit when a request carries no `maxResults`.
 */

/**
 * The Kagi-backed search provider.
 *
 * `available()` is a cheap local check and makes no network call. A key is
 * resolved per search, so storing one takes effect without a plugin restart.
 */
export class KagiSearchProvider {
  /** @param {KagiSearchProviderOptions} options - fully defaulted options from `apply`. */
  constructor(options) {
    this.options = options
    /** Stable id this provider registers under. */
    this.id = KAGI_PROVIDER_ID
  }

  /** Cheap local usability check; never makes a network call. */
  available() {
    const { apiKeyEnv, baseURL, maxResults } = this.options
    return isValidBaseUrl(baseURL)
      && isValidApiKeyEnv(apiKeyEnv)
      && (maxResults === undefined || isValidLimit(maxResults))
  }

  /**
   * Run one search through Kagi.
   *
   * @param {{ query: string, maxResults?: number }} request - the query and optional result bound.
   * @param {AbortSignal} [signal] - cancellation signal from the web seam.
   * @returns {Promise<{ sources: Array<{ url: string, title?: string, snippet?: string, publishedAt?: string }>, truncated: boolean }>}
   *   the normalized search result.
   */
  async search(request, signal) {
    const { baseURL, maxResults } = this.options
    throwIfAborted(signal)
    const apiKey = await this.apiKey(signal)
    throwIfAborted(signal)
    // A per-request bound wins over the configured default; either may be absent.
    const limit = request.maxResults ?? maxResults
    const endpoint = `${baseURL.replace(/\/+$/u, '')}/search`
    const body = {
      query: request.query,
      workflow: 'search',
      ...limit !== undefined && isValidLimit(limit) ? { limit } : {},
    }

    let response
    try {
      response = await fetch(endpoint, {
        method: 'POST',
        redirect: 'error',
        headers: {
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json',
          accept: 'application/json',
          'user-agent': USER_AGENT,
        },
        body: JSON.stringify(body),
        ...signal !== undefined ? { signal } : {},
      })
    } catch (error) {
      if (signal?.aborted === true || isAbortError(error)) throw searchAborted(signal, error)
      throw new WebError(`Kagi search request failed: ${String(error)}`, 'WEB_PROVIDER_ERROR', { cause: error })
    }

    if (!response.ok) {
      let message = `Kagi API error (HTTP ${response.status})`
      try {
        const detail = kagiErrorMessage(await response.json())
        if (detail !== undefined) message += `: ${detail}`
      } catch (error) {
        // An abort fired mid-body must surface as WEB_ABORTED, not be swallowed
        // into a generic HTTP-error message.
        if (signal?.aborted === true || isAbortError(error)) throw searchAborted(signal, error)
        // Otherwise the status is already captured; a malformed error body can
        // only cost a richer provider message, never the real error.
      }
      throw new WebError(message, 'WEB_PROVIDER_ERROR')
    }

    try {
      return mapKagiResponse(await response.json())
    } catch (error) {
      if (signal?.aborted === true || isAbortError(error)) throw searchAborted(signal, error)
      throw new WebError(
        `Kagi returned an unprocessable response body: ${String(error)}`,
        'WEB_PROVIDER_ERROR',
        { cause: error },
      )
    }
  }

  /**
   * Resolve one search's API key without retaining it on the provider.
   *
   * The credentials seam wins when mounted; otherwise the launching process
   * environment is the whole credential plane. Resolution is per operation, so
   * a changed credential reaches the next search without a restart.
   *
   * @param {AbortSignal | undefined} signal - the search's cancellation signal.
   * @returns {Promise<string>} the non-empty API key.
   * @throws {WebError} `WEB_PROVIDER_ERROR` when no key resolves, `WEB_ABORTED` on cancellation.
   */
  async apiKey(signal) {
    const { apiKeyEnv, resolveApiKey } = this.options
    throwIfAborted(signal)
    let resolved
    try {
      resolved = await abortable(resolveApiKey(), signal)
    } catch (error) {
      if (signal?.aborted === true || isAbortError(error)) throw searchAborted(signal, error)
      throw new WebError(
        `Kagi search credential resolution failed: ${String(error)}`,
        'WEB_PROVIDER_ERROR',
        { cause: error },
      )
    }
    if (typeof resolved === 'string' && resolved.length > 0) return resolved
    throw new WebError(
      `Kagi search has no API key for "${apiKeyEnv}"; store that credential through the credentials`
      + ' service or export it in the launching environment, then retry the search',
      'WEB_PROVIDER_ERROR',
    )
  }
}

/**
 * Register the Kagi search provider with `ctx.web`.
 *
 * @param {object} ctx - plugin context carrying the `web` seam and the optional `credentials` seam.
 * @param {object} [config] - patch-row config: `apiKeyEnv`, `baseURL`, `maxResults`.
 * @returns {void}
 */
export function apply(ctx, config) {
  const raw = isObject(config) ? config : {}
  const apiKeyEnv = firstString(raw.apiKeyEnv) ?? KAGI_DEFAULT_API_KEY_ENV
  const baseURL = firstString(raw.baseURL) ?? KAGI_DEFAULT_BASE_URL
  const maxResults = typeof raw.maxResults === 'number' ? raw.maxResults : undefined
  const resolveApiKey = async () => {
    const credentials = ctx.get('credentials')
    if (credentials !== undefined) {
      const resolved = await credentials.resolve(apiKeyEnv)
      if (typeof resolved?.value === 'string' && resolved.value.length > 0) return resolved.value
    }
    const ambient = process.env[apiKeyEnv]
    return typeof ambient === 'string' && ambient.length > 0 ? ambient : undefined
  }
  ctx.web.registerSearchProvider(new KagiSearchProvider({ resolveApiKey, apiKeyEnv, baseURL, maxResults }))
}
