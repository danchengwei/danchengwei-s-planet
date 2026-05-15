/**
 * 运行在页面 MAIN world：劫持 window.fetch / XMLHttpRequest，把
 * { url, method, status, 响应体前 2KB } 通过 postMessage 回传给
 * isolated world 的 content script。
 *
 * 约束：
 * - 不能用 chrome.* API（MAIN world 没有）；
 * - 只收业务向 fetch / XHR（不覆盖 img / script 的资源加载）；
 * - 响应体只抓 text / json / xml 等文本型，二进制跳过；
 * - 单条最多 2KB 正文，避免把一个大页面的网络日志撑爆内存；
 * - 轻量脱敏：高熵 token / JWT / sk-... 替换成 ***。
 */
(function () {
  const w = window as any;
  if (w.__pet_api_hook_installed__) return;
  w.__pet_api_hook_installed__ = true;

  const MAX_RESP = 2048;
  const MAX_REQ  = 512;
  const TEXT_CT  = /^(application\/(json|xml|x-www-form-urlencoded|graphql|javascript|ld\+json)|text\/)/i;
  const TOKEN_LIKE = /\b(sk-[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|[A-Za-z0-9_-]{32,})\b/g;

  let nextId = 1;

  function redact(s: string): string {
    if (!s) return s;
    return s.replace(TOKEN_LIKE, (m) => {
      if (m.length < 20) return m;
      if (/^\d+$/.test(m)) return m;
      return '***';
    });
  }
  function truncate(s: string, n: number): string {
    return s.length > n ? s.slice(0, n) + '…' : s;
  }
  function post(evt: Record<string, any>): void {
    try { window.postMessage({ __pet_api__: true, ...evt }, '*'); } catch { /* ignore */ }
  }
  function bodyToText(body: any): string | undefined {
    if (body == null) return undefined;
    if (typeof body === 'string') return body;
    if (body instanceof URLSearchParams) return body.toString();
    if (body instanceof FormData || body instanceof Blob || body instanceof ArrayBuffer) return undefined;
    try { return JSON.stringify(body); } catch { return undefined; }
  }

  /* ---------------------------- fetch ---------------------------- */
  const origFetch = w.fetch;
  if (typeof origFetch === 'function') {
    w.fetch = function (input: any, init?: any) {
      const id = nextId++;
      const t0 = performance.now();

      let url = '';
      let method = 'GET';
      try {
        if (typeof input === 'string') url = input;
        else if (input && typeof input.url === 'string') { url = input.url; method = input.method || method; }
        else if (input) url = String(input);
      } catch { /* ignore */ }
      if (init && init.method) method = init.method;
      method = String(method).toUpperCase();

      let reqSnippet: string | undefined;
      try {
        const reqTxt = init && bodyToText(init.body);
        if (reqTxt) reqSnippet = truncate(redact(reqTxt), MAX_REQ);
      } catch { /* ignore */ }

      post({ type: 'start', id, url, method, kind: 'fetch', reqSnippet, time: Date.now() });

      return origFetch.call(this, input, init).then(
        (resp: Response) => {
          const dur = Math.round(performance.now() - t0);
          const ct = (() => { try { return resp.headers.get('content-type') || ''; } catch { return ''; } })();
          let clone: Response | null = null;
          try { clone = resp.clone(); } catch { clone = null; }
          if (clone && TEXT_CT.test(ct)) {
            clone.text().then(
              (body) => post({
                type: 'end', id, url, method, kind: 'fetch',
                status: resp.status, durationMs: dur, contentType: ct,
                respSnippet: truncate(redact(body), MAX_RESP),
              }),
              () => post({ type: 'end', id, url, method, kind: 'fetch', status: resp.status, durationMs: dur, contentType: ct })
            );
          } else {
            post({ type: 'end', id, url, method, kind: 'fetch', status: resp.status, durationMs: dur, contentType: ct });
          }
          return resp;
        },
        (err: any) => {
          const dur = Math.round(performance.now() - t0);
          post({ type: 'end', id, url, method, kind: 'fetch', durationMs: dur, error: String(err && err.message || err) });
          throw err;
        }
      );
    };
  }

  /* -------------------------- console --------------------------- */
  for (const level of ['log', 'warn', 'error', 'info'] as const) {
    const orig = (console as any)[level];
    if (typeof orig !== 'function') continue;
    (console as any)[level] = function (...args: any[]) {
      try {
        const msg = args.map(formatConsoleArg).join(' ');
        post({ type: 'console', level, message: truncate(redact(msg), 600), time: Date.now() });
      } catch { /* ignore */ }
      return orig.apply(this, args);
    };
  }
  function formatConsoleArg(a: any): string {
    if (a == null) return String(a);
    if (typeof a === 'string') return a;
    if (a instanceof Error) return `${a.name}: ${a.message}`;
    if (typeof a === 'function') return `[Function ${a.name || 'anonymous'}]`;
    try { return JSON.stringify(a); } catch { return String(a); }
  }

  /* ---------------------------- eval ---------------------------- */
  // isolated world 通过 { __pet_req__:true, type:'eval', reqId, code } 请求；
  // 我们在 MAIN world 用 Function 构造器求值，把结果截断 + 脱敏后回传。
  window.addEventListener('message', (ev) => {
    if (ev.source !== window) return;
    const d: any = ev.data;
    if (!d || d.__pet_req__ !== true || d.type !== 'eval') return;
    const reqId = d.reqId;
    const code = String(d.code || '');
    void runEval(code).then((out) => {
      try { window.postMessage({ __pet_res__: true, reqId, ...out }, '*'); } catch { /* ignore */ }
    });
  });

  async function runEval(code: string): Promise<{ ok: boolean; result?: string; type?: string; error?: string }> {
    try {
      // 先当表达式：`return (code)`；表达式失败则当语句块再试一次
      let fn: Function;
      try { fn = new Function('return (' + code + ');'); }
      catch { fn = new Function(code); }
      let v = fn();
      if (v && typeof v.then === 'function') {
        v = await Promise.race([
          v,
          new Promise((_, rej) => setTimeout(() => rej(new Error('eval timeout 5s')), 5000))
        ]);
      }
      return { ok: true, type: typeName(v), result: truncate(redact(stringifyResult(v)), 4096) };
    } catch (err: any) {
      return { ok: false, error: String(err && err.message || err) };
    }
  }

  function typeName(v: any): string {
    if (v === null) return 'null';
    if (Array.isArray(v)) return 'array';
    if (v instanceof Element) return 'element';
    if (v instanceof NodeList) return 'nodelist';
    if (v instanceof Map) return 'map';
    if (v instanceof Set) return 'set';
    return typeof v;
  }

  function stringifyResult(v: any): string {
    if (v === undefined) return 'undefined';
    if (v === null) return 'null';
    if (typeof v === 'string') return JSON.stringify(v);
    if (typeof v === 'number' || typeof v === 'boolean' || typeof v === 'bigint') return String(v);
    if (typeof v === 'symbol') return v.toString();
    if (typeof v === 'function') return `[Function ${v.name || 'anonymous'}]`;
    if (v instanceof Element) return `<${v.tagName.toLowerCase()}${v.id ? ' id="' + v.id + '"' : ''}${v.className ? ' class="' + v.className + '"' : ''}>`;
    if (v instanceof NodeList) return `NodeList(${v.length})`;
    if (v instanceof Error) return `${v.name}: ${v.message}`;
    try {
      return JSON.stringify(v, (_k, val) => {
        if (typeof val === 'function') return '[Function]';
        if (val instanceof Element) return `<${val.tagName.toLowerCase()}>`;
        if (val instanceof Map) return Object.fromEntries(val);
        if (val instanceof Set) return Array.from(val);
        return val;
      }, 2);
    } catch {
      try { return String(v); } catch { return '[unserializable]'; }
    }
  }

  /* ---------------------------- XHR ---------------------------- */
  const XHR = w.XMLHttpRequest;
  if (XHR && XHR.prototype) {
    const origOpen = XHR.prototype.open;
    const origSend = XHR.prototype.send;

    XHR.prototype.open = function (method: string, url: string) {
      (this as any).__pet_info__ = { method: String(method || 'GET').toUpperCase(), url: String(url || '') };
      return origOpen.apply(this, arguments as any);
    };

    XHR.prototype.send = function (body?: any) {
      const info = (this as any).__pet_info__ || {};
      info.id = nextId++;
      info.t0 = performance.now();

      let reqSnippet: string | undefined;
      try {
        const reqTxt = bodyToText(body);
        if (reqTxt) reqSnippet = truncate(redact(reqTxt), MAX_REQ);
      } catch { /* ignore */ }

      post({ type: 'start', id: info.id, url: info.url, method: info.method, kind: 'xhr', reqSnippet, time: Date.now() });

      const self = this as XMLHttpRequest;
      const onDone = () => {
        const dur = Math.round(performance.now() - info.t0);
        const ct = (() => { try { return self.getResponseHeader('content-type') || ''; } catch { return ''; } })();
        let respSnippet: string | undefined;
        try {
          if (TEXT_CT.test(ct)) {
            const rt = self.responseType;
            const txt = (rt === '' || rt === 'text')
              ? (self.responseText || '')
              : (typeof self.response === 'string' ? self.response : '');
            if (txt) respSnippet = truncate(redact(txt), MAX_RESP);
          }
        } catch { /* ignore */ }
        post({
          type: 'end', id: info.id, url: info.url, method: info.method, kind: 'xhr',
          status: self.status, durationMs: dur, contentType: ct, respSnippet,
        });
      };
      const onErr = () => {
        const dur = Math.round(performance.now() - info.t0);
        post({ type: 'end', id: info.id, url: info.url, method: info.method, kind: 'xhr', durationMs: dur, error: 'xhr error/abort' });
      };
      self.addEventListener('load', onDone);
      self.addEventListener('error', onErr);
      self.addEventListener('abort', onErr);
      return origSend.apply(this, arguments as any);
    };
  }
})();

export {};
