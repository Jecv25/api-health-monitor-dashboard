export class ApiError extends Error {
  constructor(status, code, message, fields) {
    super(message);
    this.status = status;
    this.code = code;
    this.fields = fields;
  }
}

export const fail = (status, code, message, fields) => { throw new ApiError(status, code, message, fields); };

export function objectBody(body, allowed) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) fail(422, 'VALIDATION_ERROR', 'Submit a JSON object.');
  const extras = Object.keys(body).filter(key => !allowed.includes(key));
  if (extras.length) fail(422, 'VALIDATION_ERROR', 'Unknown fields are not accepted.', Object.fromEntries(extras.map(k => [k, 'Unknown field.'])));
}

export const behaviors = ['stable', 'flaky', 'dead', 'broken'];
export function registration(body) {
  objectBody(body, ['name', 'url', 'interval_seconds', 'demo_behavior']);
  const fields = {};
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if ([...name].length < 3 || [...name].length > 40 || /\p{Cc}/u.test(name)) fields.name = 'Enter a name of 3 to 40 characters without control characters.';
  const raw = typeof body.url === 'string' ? body.url.trim() : '';
  let url;
  try {
    url = new URL(raw);
    if (raw.length > 200 || url.protocol !== 'https:' || url.hostname !== 'api.sandbox.example' || url.username || url.password || url.port || url.search || url.hash || /[%?#\\]/.test(raw) || /(?:^|\/)\.{1,2}(?:\/|$)/.test(raw) || !/^\/[a-z][a-z0-9-]{0,39}\/health$/.test(url.pathname)) throw new Error('namespace');
  } catch { fields.url = 'Use https://api.sandbox.example/service/health with a lowercase fictional service path and no query or fragment.'; }
  const interval = body.interval_seconds === undefined ? 60 : body.interval_seconds;
  if (!Number.isInteger(interval) || interval < 10 || interval > 3600) fields.interval_seconds = 'Enter whole seconds from 10 to 3600.';
  const behavior = body.demo_behavior === undefined ? 'stable' : body.demo_behavior;
  if (!behaviors.includes(behavior)) fields.demo_behavior = 'Select a supported demo behavior.';
  if (Object.keys(fields).length) fail(422, 'VALIDATION_ERROR', 'Please correct the highlighted fields.', fields);
  return { name, url: url.href, interval_seconds: interval, demo_behavior: behavior };
}

export function positiveId(raw) {
  if (!/^[1-9]\d*$/.test(raw) || !Number.isSafeInteger(Number(raw))) fail(422, 'VALIDATION_ERROR', 'ID must be a positive integer.');
  return Number(raw);
}

export function limitValue(raw, fallback = 50, max = 100) {
  if (raw === undefined) return fallback;
  if (typeof raw !== 'string' || !/^[1-9]\d*$/.test(raw) || Number(raw) > max) fail(422, 'VALIDATION_ERROR', `Limit must be from 1 to ${max}.`);
  return Number(raw);
}
