// Thin client for the OLFA NestJS API (/v1/admin/*).
// The API address comes from /admin/config.js (window.OLFA_CONFIG.apiBase), so it
// can be set on the server without rebuilding. The session token lives in
// sessionStorage only (gone when the tab closes) and is never written to disk by us.

declare global {
  interface Window {
    OLFA_CONFIG?: { apiBase?: string };
  }
}

export const apiBase = (): string => (window.OLFA_CONFIG?.apiBase ?? '').trim().replace(/\/+$/, '');
export const apiConfigured = (): boolean => /^https:\/\//.test(apiBase()) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(apiBase());

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
  }
  /** The server could not be reached at all (offline, wrong address, CORS). */
  get unreachable() {
    return this.status === 0;
  }
}

const KEY = 'olfa.admin.session';
type Session = { token: string; mfa: boolean };

export const session = {
  get(): Session | null {
    try {
      const s = sessionStorage.getItem(KEY);
      return s ? (JSON.parse(s) as Session) : null;
    } catch {
      return null;
    }
  },
  set(s: Session) {
    try {
      sessionStorage.setItem(KEY, JSON.stringify(s));
    } catch {
      /* private mode: the session simply lasts as long as the page */
    }
    memory = s;
  },
  clear() {
    try {
      sessionStorage.removeItem(KEY);
    } catch {
      /* ignore */
    }
    memory = null;
  },
};
let memory: Session | null = null;
const current = () => session.get() ?? memory;

let onUnauthorized: () => void = () => {};
let onTotpSetup: () => void = () => {};
/** Called when the session ends (401) and when the server asks for two-factor set-up first (403). */
export const setSessionHandlers = (unauthorized: () => void, totpSetup: () => void) => {
  onUnauthorized = unauthorized;
  onTotpSetup = totpSetup;
};

export async function api<T = unknown>(method: 'GET' | 'POST' | 'PUT' | 'DELETE', path: string, body?: unknown, query?: Record<string, string | number | undefined>): Promise<T> {
  if (!apiConfigured()) throw new ApiError(0, 'NOT_CONFIGURED', 'API address is not configured');
  const qs = query
    ? '?' +
      Object.entries(query)
        .filter(([, v]) => v !== undefined && v !== '')
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
        .join('&')
    : '';
  const s = current();
  let res: Response;
  try {
    res = await fetch(`${apiBase()}/v1/admin/${path}${qs}`, {
      method,
      headers: { Accept: 'application/json', ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...(s ? { Authorization: `Bearer ${s.token}` } : {}) },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      credentials: 'omit',
      cache: 'no-store',
    });
  } catch {
    throw new ApiError(0, 'UNREACHABLE', 'The server could not be reached');
  }
  if (res.status === 204) return undefined as T;
  const json = (await res.json().catch(() => null)) as { error?: { code: string; message: string; details?: Record<string, unknown> } } | null;
  if (!res.ok) {
    const e = json?.error;
    const err = new ApiError(res.status, e?.code ?? 'HTTP_' + res.status, e?.message ?? res.statusText, e?.details);
    if (res.status === 401 && path !== 'auth/login') {
      session.clear();
      onUnauthorized();
    }
    if (res.status === 403 && e?.details?.totpSetupRequired) onTotpSetup();
    throw err;
  }
  return json as T;
}

export const GET = <T>(p: string, q?: Record<string, string | number | undefined>) => api<T>('GET', p, undefined, q);
export const POST = <T>(p: string, b: unknown = {}) => api<T>('POST', p, b);
export const PUT = <T>(p: string, b: unknown = {}) => api<T>('PUT', p, b);
export const DEL = <T>(p: string) => api<T>('DELETE', p);

/** Uploads one support attachment: presigned POST straight to storage, returns its id. */
export async function uploadAttachment(file: File): Promise<string> {
  const r = await POST<{ id: string; upload: { url: string; fields: Record<string, string> } }>('support/attachments', { fileName: file.name.slice(0, 120), mime: file.type, bytes: file.size });
  const form = new FormData();
  for (const [k, v] of Object.entries(r.upload.fields)) form.append(k, v);
  form.append('file', file);
  const up = await fetch(r.upload.url, { method: 'POST', body: form });
  if (!up.ok) throw new ApiError(up.status, 'UPLOAD_FAILED', 'Upload failed');
  return r.id;
}
