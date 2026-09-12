/* simpler yourMark — files stay in this tab */
(() => {
  const GUIDE_ID = "guide";
  const GUIDE_CARDS = [
    ["Browser preview", "Files stay in this tab. Nothing is uploaded. No OCR here — scans need the Mac app."],
    ["Mac app", "OCR, layout, Translate, and Finder. The Mac app link opens the GitHub intro."],
    ["Convert", "Drop a PDF with selectable text, Word, or ready Markdown. Pictures in the PDF become blue Figure links."],
    ["Library", "Cards on the left. Search in files filters them. × removes a file from this browser only."],
    ["Hunter / FORAGE", "Turn Hunter on, select a passage, press Enter. Clips go on today’s FORAGE note."],
    ["Ask", "Answers come from the open chapter. AND, OR, and NOT must be capitals, in the same sentence."],
    ["Edit", "Download, then open in MarkEdit (Mac) or MarkText (Windows). Both are free."],
    ["Languages", "US English, Spanish, or Dutch for this preview. The Mac app can add more with an Ask key."],
    ["Translate", "From and To on the reader. Below, Replace, or SIDE BY SIDE. Save a copy writes a second card."],
    ["Share", "Copy puts Markdown on the clipboard. Nothing is uploaded unless you press Ask or Translate."],
  ];

  const DEMO_ID = "demo";
  const DEMO = `# Landing gear

The landing gear supports the aeroplane on the ground and absorbs the shock of landing.

[Figure, page 1](shots/intro-figure.jpg)

Flaps increase lift at low speed when landing. Slats do the same at the leading edge.

Ice on the gear is a separate problem from flap position.

## Extension

The gear extends before landing. The doors open, the legs lock down, and the lights confirm.

## Retraction

After takeoff the gear retracts. Doors close. A horn sounds if the gear is up while the aeroplane is configured to land.

## Ask this chapter

Try: \`flaps AND landing NOT ice\`. AND, OR, and NOT must be capitals, in the same sentence.
`;

  const TR_LANGS = [
    ["auto", "Detect"],
    ["en", "English"],
    ["es", "Spanish"],
    ["nl", "Dutch"],
    ["zh-CN", "Chinese"],
    ["fr", "French"],
    ["de", "German"],
    ["ja", "Japanese"],
    ["it", "Italian"],
    ["pt", "Portuguese"],
  ];

  const GUIDE = `# Getting started with yourMark

This site is a **browser preview**. The browser version does **not** include OCR.

The [Mac app](https://github.com/Burbank/yourMark) is better for PDFs with graphics — OCR and layout. Scans, tables, and figures stay intact there.

**Hunter-Gatherer:** select text and press Enter. Each clip keeps its heading and lands on a dated **FORAGE** note.

**Ask:** AND, OR, and NOT must be capitals, and the words must sit in the same sentence.
`;

  const I18N = {
    en: {
      tabLibrary: "Library",
      tabConvert: "Convert",
      tabSettings: "Settings",
      libSearch: "Search in files…",
      find: "Find in chapter",
      hunter: "Hunter",
      forage: "FORAGE",
      askPh: "What does this chapter say about…",
      addForage: "Add to Forage",
      copy: "Copy",
      translate: "Translate",
    },
    es: {
      tabLibrary: "Biblioteca",
      tabConvert: "Convertir",
      tabSettings: "Ajustes",
      libSearch: "Buscar en archivos…",
      find: "Buscar en el capítulo",
      hunter: "Hunter",
      forage: "FORAGE",
      askPh: "Qué dice este capítulo sobre…",
      addForage: "Añadir a Forage",
      copy: "Copiar",
      translate: "Traducir",
    },
    nl: {
      tabLibrary: "Bibliotheek",
      tabConvert: "Converteren",
      tabSettings: "Instellingen",
      libSearch: "Zoeken in bestanden…",
      find: "Zoeken in hoofdstuk",
      hunter: "Hunter",
      forage: "FORAGE",
      askPh: "Wat zegt dit hoofdstuk over…",
      addForage: "Toevoegen aan Forage",
      copy: "Kopiëren",
      translate: "Vertalen",
    },
  };

  pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";

  const $ = (id) => document.getElementById(id);
  const state = {
    tab: "library",
    files: [],
    current: GUIDE_ID,
    rendered: true,
    hunterOn: false,
    hideLib: false,
    lastAsk: "",
    lastAnswer: "",
    askHistory: JSON.parse(sessionStorage.getItem("yourmark-asks") || "[]"),
    tr: { from: "en", to: "zh-CN", mode: "below", text: "", busy: false },
    settings: loadSettings(),
  };

  function loadSettings() {
    try {
      return Object.assign(
        {
          theme: "bright",
          font: "Atkinson Hyperlegible",
          fontSize: 18,
          stripChrome: true,
          provider: "openai",
          key: "",
          googleKey: "",
          trEngine: "preview",
          figSize: 320,
          lang: "en",
          hideHero: false,
        },
        JSON.parse(localStorage.getItem("yourmark-settings") || "{}")
      );
    } catch {
      return { theme: "bright", font: "Atkinson Hyperlegible", fontSize: 18, stripChrome: true, provider: "openai", key: "", googleKey: "", trEngine: "preview", figSize: 320, lang: "en", hideHero: false };
    }
  }
  function saveSettings() {
    const { key, googleKey, ...rest } = state.settings;
    localStorage.setItem(
      "yourmark-settings",
      JSON.stringify({ ...rest, key: key ? "set" : "", googleKey: googleKey ? "set" : "" })
    );
    sessionStorage.setItem("yourmark-key", state.settings.key || "");
    sessionStorage.setItem("yourmark-gkey", state.settings.googleKey || "");
  }
  if (sessionStorage.getItem("yourmark-key")) {
    state.settings.key = sessionStorage.getItem("yourmark-key");
  } else if (state.settings.key === "set") {
    state.settings.key = "";
  }
  if (sessionStorage.getItem("yourmark-gkey")) {
    state.settings.googleKey = sessionStorage.getItem("yourmark-gkey");
  } else if (state.settings.googleKey === "set") {
    state.settings.googleKey = "";
  }

  function dbp() {
    return new Promise((resolve, reject) => {
      const r = indexedDB.open("yourmark-web", 1);
      r.onupgradeneeded = () => r.result.createObjectStore("files", { keyPath: "id" });
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    });
  }
  async function dbAll() {
    const db = await dbp();
    return new Promise((resolve, reject) => {
      const q = db.transaction("files").objectStore("files").getAll();
      q.onsuccess = () => resolve(q.result || []);
      q.onerror = () => reject(q.error);
    });
  }
  async function dbPut(file) {
    const db = await dbp();
    return new Promise((resolve, reject) => {
      const q = db.transaction("files", "readwrite").objectStore("files").put(file);
      q.onsuccess = () => resolve();
      q.onerror = () => reject(q.error);
    });
  }
  async function dbDel(id) {
    const db = await dbp();
    return new Promise((resolve, reject) => {
      const q = db.transaction("files", "readwrite").objectStore("files").delete(id);
      q.onsuccess = () => resolve();
      q.onerror = () => reject(q.error);
    });
  }

  function applyTheme() {
    let t = state.settings.theme;
    if (t === "system") t = matchMedia("(prefers-color-scheme: dark)").matches ? "dim" : "bright";
    document.documentElement.setAttribute("data-theme", t === "dim" ? "dim" : "bright");
    document.querySelectorAll("#theme-seg button").forEach((b) => {
      b.classList.toggle("on", b.dataset.theme === state.settings.theme);
    });
  }

  function bookmarksFrom(md, outline) {
    if (outline && outline.length) return outline;
    const out = [];
    md.split("\n").forEach((line, i) => {
      const m = line.match(/^(#{1,6})\s+(.*)/);
      if (m) out.push({ title: m[2].replace(/\s+/g, " ").trim(), level: m[1].length, line: i });
    });
    return out;
  }

  function headingize(line) {
    const m = line.match(/^(\d+(?:\.\d+){0,5})\s+(\S.{2,90})$/);
    if (!m) return line;
    const depth = Math.min(m[1].split(".").length, 6);
    return "#".repeat(depth) + " " + m[1] + " " + m[2].trim();
  }

  function norm(s) {
    return s.toLowerCase().replace(/\s+/g, " ").replace(/[\d./:-]+/g, "#").trim();
  }

  function chromeSet(pages) {
    const n = pages.length;
    if (n < 3) return new Set();
    const counts = {};
    for (const lines of pages) {
      const slice = [...lines.slice(0, 2), ...lines.slice(-2)];
      for (const l of slice) {
        const k = norm(l);
        if (k.length >= 4 && k.length < 70) counts[k] = (counts[k] || 0) + 1;
      }
    }
    const need = Math.max(3, Math.floor(n * 0.45));
    return new Set(Object.keys(counts).filter((k) => counts[k] >= need));
  }

  function itemsToLines(items) {
    if (!items || !items.length) return [];
    const rows = new Map();
    for (const it of items) {
      if (!it || !it.transform) continue;
      const y = Math.round((it.transform[5] || 0) / 3) * 3;
      const x = it.transform[4] || 0;
      const rec = rows.get(y) || [];
      rec.push({ x, s: it.str || "" });
      rows.set(y, rec);
    }
    return [...rows.entries()]
      .sort((a, b) => b[0] - a[0])
      .map(([, bits]) =>
        bits
          .sort((a, b) => a.x - b.x)
          .map((b) => b.s)
          .join(" ")
          .replace(/\s+/g, " ")
          .trim()
      )
      .filter(Boolean);
  }

  function rawToJpeg(img) {
    try {
      const c = document.createElement("canvas");
      c.width = img.width;
      c.height = img.height;
      const ctx = c.getContext("2d");
      if (img.data instanceof Uint8ClampedArray || img.data instanceof Uint8Array) {
        const n = img.width * img.height * 4;
        const rgba = new Uint8ClampedArray(n);
        const k = img.data.length / (img.width * img.height);
        if (k >= 3) {
          for (let i = 0, p = 0; i < img.data.length; i += k, p += 4) {
            rgba[p] = img.data[i];
            rgba[p + 1] = img.data[i + 1];
            rgba[p + 2] = img.data[i + 2];
            rgba[p + 3] = 255;
          }
        } else return "";
        ctx.putImageData(new ImageData(rgba, img.width, img.height), 0, 0);
        return c.toDataURL("image/jpeg", 0.78);
      }
    } catch {
      return "";
    }
    return "";
  }

  async function imagesOnPage(page) {
    const out = [];
    try {
      if (!page || !page.objs || typeof page.objs.get !== "function") return out;
      const ops = await page.getOperatorList();
      if (!ops || !ops.fnArray) return out;
      const names = new Set();
      const paintImg = pdfjsLib.OPS && pdfjsLib.OPS.paintImageXObject;
      const paintX = pdfjsLib.OPS && pdfjsLib.OPS.paintXObject;
      for (let i = 0; i < ops.fnArray.length; i++) {
        const fn = ops.fnArray[i];
        if (fn === paintImg || fn === paintX) {
          const n = ops.argsArray[i] && ops.argsArray[i][0];
          if (typeof n === "string") names.add(n);
        }
      }
      for (const name of names) {
        const obj = await new Promise((resolve) => {
          try {
            page.objs.get(name, resolve);
          } catch {
            resolve(null);
          }
        });
        if (!obj || !obj.width || obj.width < 90 || obj.height < 90) continue;
        if (obj.width * obj.height > 4_000_000) continue;
        const url = rawToJpeg(obj);
        if (url) out.push(url);
        if (out.length >= 6) break;
      }
    } catch {
      /* pictures are best-effort in the browser */
    }
    return out;
  }

  async function renderPageJpeg(page, scale) {
    const vp = page.getViewport({ scale: scale || 1.25 });
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.floor(vp.width));
    canvas.height = Math.max(1, Math.floor(vp.height));
    const ctx = canvas.getContext("2d", { alpha: false });
    const task = page.render({ canvasContext: ctx, viewport: vp });
    if (task && task.promise) await task.promise;
    return canvas;
  }

  async function startOcrWorker() {
    if (!window.Tesseract || typeof Tesseract.createWorker !== "function") return null;
    try {
      return await Tesseract.createWorker("eng", 1, {
        workerPath: "https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/worker.min.js",
        corePath: "https://cdn.jsdelivr.net/npm/tesseract.js-core@5.1.0/tesseract-core.wasm.js",
        langPath: "https://tessdata.projectnaptha.com/4.0.0",
      });
    } catch {
      return null;
    }
  }

  async function ocrScan(pdf, onStatus) {
    const n = Math.min(pdf.numPages || 1, 40);
    const parts = [
      "> This PDF is a **scan** (a picture of each page). This tab reads the words here. The Mac app does this better.",
      "",
    ];
    onStatus("Scan — preparing OCR…");
    const worker = await startOcrWorker();
    for (let i = 1; i <= n; i++) {
      onStatus("Scan — page " + i + " of " + n + "…");
      try {
        const page = await pdf.getPage(i);
        const canvas = await renderPageJpeg(page, worker ? 1.35 : 1.15);
        const jpeg = canvas.toDataURL("image/jpeg", 0.7);
        parts.push("## Page " + i, "", "![Page " + i + "](" + jpeg + ")", "");
        if (worker) {
          try {
            const result = await worker.recognize(canvas);
            const text = result && result.data && result.data.text ? String(result.data.text).trim() : "";
            if (text) parts.push(text, "");
          } catch {
            parts.push("_Could not read the words on this page._", "");
          }
        }
      } catch {
        parts.push("## Page " + i, "", "_Could not draw this page._", "");
      }
    }
    if (worker && typeof worker.terminate === "function") {
      try { await worker.terminate(); } catch (_) {}
    }
    if (!worker) {
      parts.push("_This browser could not start OCR. Page pictures are kept. The Mac app will read the words._", "");
    }
    return parts.join("\n");
  }

  function scanNotice(name, pages) {
    const n = pages || 1;
    const pageWord = n === 1 ? "1 page" : n + " pages";
    return [
      "# This PDF is a scan",
      "",
      "**" + String(name).replace(/[#*_]/g, "") + "** looks like a photograph of " + pageWord + ", not selectable text.",
      "",
      "This site is a **browser preview**. It does **not** include OCR. It only copies words that are already in the file. Nothing was uploaded.",
      "",
      "The **Mac app** is better for PDFs with graphics — OCR and layout. Scans, tables, and figures stay intact there.",
      "",
      "[Mac app on GitHub](https://github.com/Burbank/yourMark)",
      "",
    ].join("\n");
  }

  async function outlineOf(pdf) {
    try {
      const tree = await pdf.getOutline();
      if (!tree || !tree.length) return [];
      const flat = [];
      const walk = (nodes, level) => {
        for (const n of nodes || []) {
          if (n.title) flat.push({ title: n.title.trim(), level: Math.min(level, 6), line: 0 });
          if (n.items) walk(n.items, level + 1);
        }
      };
      walk(tree, 1);
      return flat;
    } catch {
      return [];
    }
  }

  function pdfBytes(buf) {
    const src = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
    const copy = new Uint8Array(src.byteLength);
    copy.set(src);
    return copy;
  }

  async function openPdf(buf) {
    if (!window.pdfjsLib || typeof pdfjsLib.getDocument !== "function") {
      throw new Error("PDF reader did not load. Refresh this page.");
    }
    const data = pdfBytes(buf);
    try {
      return await pdfjsLib.getDocument({ data, verbosity: 0 }).promise;
    } catch (err) {
      try {
        return await pdfjsLib.getDocument({ data: pdfBytes(buf), disableWorker: true, verbosity: 0 }).promise;
      } catch {
        throw err;
      }
    }
  }

  async function convertPdf(buf, name, onStatus) {
    const pdf = await openPdf(buf);
    const pages = [];
    const n = Math.min(pdf.numPages || 1, 400);
    let letters = 0;
    for (let i = 1; i <= n; i++) {
      const page = await pdf.getPage(i);
      let lines = [];
      try {
        const tc = await page.getTextContent();
        const items = tc && Array.isArray(tc.items) ? tc.items : [];
        lines = itemsToLines(items);
      } catch {
        lines = [];
      }
      letters += lines.join(" ").replace(/[^a-zA-Z]/g, "").length;
      pages.push(lines);
    }
    const scan = n > 0 && letters < n * 40;
    if (scan) {
      onStatus && onStatus("This PDF is a scan.");
      const md = scanNotice(name, n);
      return { markdown: md, bookmarks: bookmarksFrom(md, []), name, scan: true };
    }
    const chrome = state.settings.stripChrome ? chromeSet(pages) : new Set();
    const parts = [];
    const imgPages = Math.min(n, 80);
    for (let i = 0; i < n; i++) {
      const body = (pages[i] || [])
        .filter((l) => !chrome.has(norm(l)))
        .filter((l) => !/^\s*\d+\s*$/.test(l))
        .map(headingize);
      const figs = [];
      if (i < imgPages) {
        try {
          const page = await pdf.getPage(i + 1);
          const urls = await imagesOnPage(page);
          urls.forEach((url, fi) => {
            figs.push("[Figure, page " + (i + 1) + (urls.length > 1 ? "." + (fi + 1) : "") + "](" + url + ")");
          });
        } catch (_) {}
      }
      if (!body.length && !figs.length) continue;
      parts.push("<!-- page " + (i + 1) + " -->", "");
      if (figs.length) parts.push.apply(parts, figs.concat([""]));
      if (body.length) parts.push.apply(parts, body.concat([""]));
    }
    let md = parts.join("\n").trim();
    if (!md) md = "_No selectable text in this PDF. Scans need OCR — try again, or the Mac app._";
    const outline = await outlineOf(pdf);
    return { markdown: md, bookmarks: bookmarksFrom(md, outline), name };
  }

  async function convertDocx(buf, name) {
    const { value } = await mammoth.convertToHtml({ arrayBuffer: buf });
    let html = value || "";
    html = html
      .replace(/<h1[^>]*>/gi, "\n# ")
      .replace(/<h2[^>]*>/gi, "\n## ")
      .replace(/<h3[^>]*>/gi, "\n### ")
      .replace(/<\/h[1-6]>/gi, "\n")
      .replace(/<li[^>]*>/gi, "\n- ")
      .replace(/<p[^>]*>/gi, "\n\n")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, "")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"');
    const md = html.replace(/\n{3,}/g, "\n\n").trim() || "_Empty Word file._";
    return { markdown: md, bookmarks: bookmarksFrom(md, []), name };
  }

  function uid() {
    return "f" + Math.random().toString(36).slice(2, 10);
  }

  function demoFile() {
    return { id: DEMO_ID, title: "Landing gear (sample)", kind: "DEMO", markdown: DEMO, bookmarks: bookmarksFrom(DEMO, []) };
  }

  function currentFile() {
    if (state.current === GUIDE_ID) {
      return { id: GUIDE_ID, title: "Getting started with yourMark", kind: "GUIDE", markdown: GUIDE, bookmarks: bookmarksFrom(GUIDE, []) };
    }
    if (state.current === DEMO_ID) return demoFile();
    return state.files.find((f) => f.id === state.current) || null;
  }

  function booleanHit(hay, query) {
    const q = String(query || "").trim();
    if (!q) return true;
    const parts = q.split(/\s+/);
    const sents = String(hay).split(/(?<=[.?!])\s+|\n+/);
    const testSent = (sent) => {
      const low = sent.toLowerCase();
      let ok = null;
      let mode = "AND";
      let pendingNot = false;
      for (const raw of parts) {
        if (raw === "AND" || raw === "OR") {
          mode = raw;
          continue;
        }
        if (raw === "NOT") {
          pendingNot = true;
          continue;
        }
        const word = raw.replace(/^["']|["']$/g, "").toLowerCase();
        if (!word) continue;
        const has = low.includes(word);
        const bit = pendingNot ? !has : has;
        pendingNot = false;
        ok = ok == null ? bit : mode === "OR" ? ok || bit : ok && bit;
      }
      return !!ok;
    };
    if (/\b(AND|OR|NOT)\b/.test(q)) return sents.some(testSent);
    return hay.toLowerCase().includes(q.toLowerCase());
  }

  function renderCards() {
    const box = $("cards");
    const q = ($("lib-search") && $("lib-search").value) || "";
    const items = [
      { id: GUIDE_ID, title: "Getting started with yourMark", kind: "GUIDE", markdown: GUIDE },
      demoFile(),
      ...state.files.map((f) => ({ id: f.id, title: f.title, kind: f.kind || "MARKDOWN", markdown: f.markdown })),
    ].filter((it) => !q || booleanHit(it.title + "\n" + (it.markdown || ""), q));
    box.innerHTML = items
      .map(
        (it) => `<div class="card ${it.id === state.current ? "on" : ""}" data-id="${it.id}">
        ${it.id === GUIDE_ID || it.id === DEMO_ID ? "" : `<button class="del" data-del="${it.id}" title="Remove">×</button>`}
        <small>${it.kind}${q ? " · match" : ""}</small>${escapeHtml(it.title)}</div>`
      )
      .join("") || `<p class="muted">No cards match.</p>`;
  }

  function renderToc() {
    const f = currentFile();
    const box = $("toc");
    if (!f) {
      box.innerHTML = "";
      return;
    }
    const marks = f.bookmarks || bookmarksFrom(f.markdown, []);
    box.innerHTML =
      `<div class="k">Bookmarks</div>` +
      marks
        .map(
          (b, i) =>
            `<button class="l${Math.min(b.level || 1, 3)}" data-jump="${i}">${escapeHtml(b.title)}</button>`
        )
        .join("");
  }

  function mdToHtml(md) {
    try {
      if (window.marked && typeof marked.parse === 'function') return marked.parse(md);
      if (typeof marked === 'function') return marked(md);
    } catch (e) {}
    return String(md).replace(/</g, '&' + 'lt;');
  }

  function paintMarkdown(el, md) {
    el.style.fontFamily = state.settings.font;
    el.style.fontSize = state.settings.fontSize + "px";
    const html = mdToHtml(md);
    el.innerHTML = DOMPurify.sanitize(html, { ADD_TAGS: ["img"], ADD_ATTR: ["src", "alt", "href"] });
    decorateFigures(el);
  }

  function belowMarkdown(orig, trans) {
    const a = orig.split(/\n{2,}/);
    const b = trans.split(/\n{2,}/);
    const n = Math.max(a.length, b.length);
    const out = [];
    for (let i = 0; i < n; i++) {
      if (a[i]) out.push(a[i]);
      if (b[i] && b[i] !== a[i]) out.push("> " + b[i].replace(/\n/g, "\n> "));
    }
    return out.join("\n\n");
  }

  function renderReader() {
    const f = currentFile();
    $("reader-title").textContent = f ? f.title : "";
    $("md-view").style.fontFamily = state.settings.font;
    $("md-view").style.fontSize = state.settings.fontSize + "px";
    $("md-src").style.fontSize = Math.max(13, state.settings.fontSize - 2) + "px";
    const pair = $("md-pair");
    if (!f) {
      $("md-view").innerHTML = "";
      $("md-src").textContent = "";
      if (pair) pair.hidden = true;
      return;
    }
    $("md-src").textContent = f.markdown;
    const side = state.rendered && state.tr.mode === "side" && state.tr.text;
    if (pair) pair.hidden = !side;
    if (f.id === GUIDE_ID && state.rendered && !side) {
      $("md-view").innerHTML = GUIDE_CARDS.map(
        ([h, p]) => `<article><h3>${h}</h3><p>${p}</p></article>`
      ).join("");
      $("md-view").classList.add("help-grid");
    } else {
      $("md-view").classList.remove("help-grid");
      let md = f.markdown;
      if (state.tr.text && state.tr.mode === "replace") md = state.tr.text;
      else if (state.tr.text && state.tr.mode === "below") md = belowMarkdown(f.markdown, state.tr.text);
      paintMarkdown($("md-view"), md);
      highlightFind();
    }
    if (side) {
      paintMarkdown($("md-left"), f.markdown);
      paintMarkdown($("md-right"), state.tr.text);
      const left = $("md-left");
      const right = $("md-right");
      const on = $("tr-sync") && $("tr-sync").checked;
      left.onscroll = on ? () => { right.scrollTop = left.scrollTop; } : null;
      right.onscroll = on ? () => { left.scrollTop = right.scrollTop; } : null;
    }
    $("md-view").hidden = !state.rendered || !!side;
    $("md-src").hidden = state.rendered;
    $("btn-rendered").classList.toggle("on", state.rendered);
    $("btn-source").classList.toggle("on", !state.rendered);
    document.querySelectorAll("[data-tr-mode]").forEach((b) => b.classList.toggle("on", b.dataset.trMode === state.tr.mode));
  }

  function isFigHref(href) {
    if (!href) return false;
    return /^(data:image|shots\/|\.\/shots\/)/.test(href) || /\.(jpe?g|png|gif|webp)(\?|#|$)/i.test(href);
  }

  function decorateFigures(root) {
    (root || $("md-view")).querySelectorAll("a[href]").forEach((a) => {
      const href = a.getAttribute("href");
      if (!isFigHref(href)) return;
      a.classList.add("fig-link");
      a.addEventListener("mouseenter", (e) => showFig(e, href));
      a.addEventListener("mouseleave", hideFig);
    });
  }

  function showFig(e, href) {
    const pop = $("fig-pop");
    if (!pop) return;
    pop.hidden = false;
    pop.innerHTML = '<img alt="" src="' + href + '">';
    const x = Math.min(e.clientX + 16, window.innerWidth - 320);
    const y = Math.min(e.clientY + 16, window.innerHeight - 240);
    pop.style.left = x + "px";
    pop.style.top = y + "px";
  }
  function hideFig() {
    const pop = $("fig-pop");
    if (pop) pop.hidden = true;
  }

  function highlightFind() {
    const q = (($("find-q") && $("find-q").value) || "").trim();
    if (!q || !state.rendered) return;
    const view = $("md-view");
    const walk = document.createTreeWalker(view, NodeFilter.SHOW_TEXT);
    const hits = [];
    while (walk.nextNode()) {
      const node = walk.currentNode;
      if (!node.nodeValue || !node.nodeValue.toLowerCase().includes(q.toLowerCase())) continue;
      hits.push(node);
    }
    hits.forEach((node) => {
      const re = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "ig");
      const frag = document.createDocumentFragment();
      let last = 0;
      const text = node.nodeValue;
      text.replace(re, (m, i) => {
        frag.appendChild(document.createTextNode(text.slice(last, i)));
        const mark = document.createElement("mark");
        mark.textContent = m;
        frag.appendChild(mark);
        last = i + m.length;
        return m;
      });
      frag.appendChild(document.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(frag, node);
    });
  }

  function todayForageTitle() {
    const d = new Date();
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day + " FORAGE";
  }

  async function forageFile() {
    const title = todayForageTitle();
    let item = state.files.find((f) => f.title === title && f.kind === "FORAGE");
    if (!item) {
      item = {
        id: uid(),
        title,
        kind: "FORAGE",
        markdown: "# " + title + "\n\nClips stay in this browser.\n",
        bookmarks: [],
        at: Date.now(),
      };
      state.files.unshift(item);
      await dbPut(item);
    }
    return item;
  }

  async function addToForage(passage, src) {
    const text = String(passage || "").trim();
    if (!text) return;
    const item = await forageFile();
    const f = currentFile();
    const head = (src || (f && f.title) || "clip").replace(/\n/g, " ");
    item.markdown += "\n## " + head + "\n\n" + text + "\n";
    item.bookmarks = bookmarksFrom(item.markdown, []);
    item.at = Date.now();
    await dbPut(item);
    renderCards();
  }

  function applyLang() {
    const pack = I18N[state.settings.lang] || I18N.en;
    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const k = el.getAttribute("data-i18n");
      if (pack[k]) el.textContent = pack[k];
    });
    if ($("lib-search")) $("lib-search").placeholder = pack.libSearch;
    if ($("find-q")) $("find-q").placeholder = pack.find;
    if ($("btn-hunter")) $("btn-hunter").textContent = pack.hunter;
    if ($("btn-forage")) $("btn-forage").textContent = pack.forage;
    if ($("ask-q")) $("ask-q").placeholder = pack.askPh;
    if ($("btn-add-forage")) $("btn-add-forage").textContent = pack.addForage;
    if ($("btn-copy")) $("btn-copy").textContent = pack.copy;
    if ($("btn-tr")) $("btn-tr").textContent = pack.translate;
    document.documentElement.lang = state.settings.lang || "en";
  }

  function fillTrLangs() {
    const from = $("tr-from");
    const to = $("tr-to");
    if (!from || !to) return;
    from.innerHTML = TR_LANGS.map(([id, lab]) => `<option value="${id}">${lab}</option>`).join("");
    to.innerHTML = TR_LANGS.filter(([id]) => id !== "auto")
      .map(([id, lab]) => `<option value="${id}">${lab}</option>`)
      .join("");
    from.value = state.tr.from;
    to.value = state.tr.to;
  }

  function chunkText(text, max) {
    const parts = [];
    let buf = "";
    String(text || "")
      .split(/\n{2,}/)
      .forEach((p) => {
        if ((buf + "\n\n" + p).length > max && buf) {
          parts.push(buf);
          buf = p;
        } else buf = buf ? buf + "\n\n" + p : p;
      });
    if (buf) parts.push(buf);
    return parts;
  }

  async function translateViaMemory(text, from, to) {
    const src = from === "auto" ? "en" : from;
    const chunks = chunkText(text, 420);
    const out = [];
    for (const chunk of chunks) {
      const url =
        "https://api.mymemory.translated.net/get?q=" +
        encodeURIComponent(chunk) +
        "&langpair=" +
        encodeURIComponent(src + "|" + to);
      const r = await fetch(url);
      if (!r.ok) throw new Error("HTTP " + r.status);
      const j = await r.json();
      const t = j && j.responseData && j.responseData.translatedText;
      if (!t) throw new Error("empty");
      out.push(t);
    }
    return out.join("\n\n");
  }

  async function translateViaGoogle(text, from, to) {
    const r = await fetch("https://translation.googleapis.com/language/translate/v2?key=" + encodeURIComponent(state.settings.googleKey), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        q: chunkText(text, 4000),
        source: from === "auto" ? undefined : from,
        target: to,
        format: "text",
      }),
    });
    if (!r.ok) throw new Error("HTTP " + r.status);
    const j = await r.json();
    const bits = (((j.data || {}).translations) || []).map((x) => x.translatedText);
    if (!bits.length) throw new Error("empty");
    return bits.join("\n\n");
  }

  async function translateViaAsk(text, to) {
    const url =
      state.settings.provider === "xai"
        ? "https://api.x.ai/v1/chat/completions"
        : "https://api.openai.com/v1/chat/completions";
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + state.settings.key },
      body: JSON.stringify({
        model: state.settings.provider === "xai" ? "grok-3" : "gpt-4o-mini",
        max_tokens: 2000,
        messages: [
          { role: "system", content: "Translate the Markdown to " + to + ". Keep headings and links. Do not add commentary." },
          { role: "user", content: text.slice(0, 8000) },
        ],
      }),
    });
    if (!r.ok) throw new Error("HTTP " + r.status);
    const j = await r.json();
    return (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || "";
  }

  async function runTranslate() {
    const f = currentFile();
    if (!f || state.tr.busy) return;
    state.tr.from = $("tr-from").value;
    state.tr.to = $("tr-to").value;
    state.tr.busy = true;
    $("tr-status").textContent = "Translating this chapter…";
    const raw = chapterText().slice(0, 6000) || f.markdown.slice(0, 6000);
    const holes = [];
    const src = String(raw).replace(/\[[^\]]+\]\([^)]+\)/g, (m) => {
      holes.push(m);
      return "[[" + (holes.length - 1) + "]]";
    });
    try {
      let text = "";
      const engine = state.settings.trEngine;
      if (engine === "google" && state.settings.googleKey) text = await translateViaGoogle(src, state.tr.from, state.tr.to);
      else if (engine === "ask" && state.settings.key) text = await translateViaAsk(src, state.tr.to);
      else text = await translateViaMemory(src, state.tr.from, state.tr.to);
      if (!text.trim()) throw new Error("empty");
      text = text.replace(/\[\[\s*(\d+)\s*\]\]/g, (_, i) => holes[+i] || "");
      state.tr.text = text.trim();
      $("tr-status").textContent = "Done. Original is unchanged. Save a copy writes a second card.";
      renderReader();
    } catch (err) {
      $("tr-status").textContent =
        "Could not translate here (" + (err && err.message ? err.message : "blocked") + "). Try another engine, or the Mac app.";
    } finally {
      state.tr.busy = false;
    }
  }

  async function saveTranslation() {
    if (!state.tr.text) {
      $("tr-status").textContent = "Translate first, then save a copy.";
      return;
    }
    const f = currentFile();
    const item = {
      id: uid(),
      title: (f && f.title ? f.title : "file") + "." + state.tr.to,
      kind: "MARKDOWN",
      markdown: state.tr.text,
      bookmarks: bookmarksFrom(state.tr.text, []),
      at: Date.now(),
    };
    await dbPut(item);
    state.files.unshift(item);
    state.current = item.id;
    state.tr.text = "";
    showTab("library");
  }

  function applyHero() {
    document.getElementById("app").classList.toggle("hero-off", !!state.settings.hideHero);
  }

  function showAskAnswer(q, body) {
    state.lastAsk = q;
    state.lastAnswer = body;
    $("ask-ans").hidden = false;
    $("ask-ans-q").textContent = q;
    $("ask-ans-body").textContent = body;
  }

  function escapeHtml(s) {
    const map = {
      '&': '&' + 'amp;',
      '<': '&' + 'lt;',
      '>': '&' + 'gt;',
      '"': '&' + 'quot;',
      "'": '&' + '#39;'
    };
    return String(s).replace(/[&<>"']/g, function (c) { return map[c]; });
  }

  function showTab(tab) {
    state.tab = tab;
    $("view-library").hidden = tab !== "library";
    $("view-convert").hidden = tab !== "convert";
    $("view-settings").hidden = tab !== "settings";
    $("ask-bar").hidden = tab !== "library";
    document.querySelectorAll(".tabs button").forEach((b) => b.classList.toggle("on", b.dataset.tab === tab));
    $("btn-settings").classList.toggle("on", tab === "settings");
    $("view-library").classList.toggle("hide-lib", !!state.hideLib);
    $("btn-hunter").classList.toggle("on", !!state.hunterOn);
    if (tab === "library") {
      renderCards();
      renderToc();
      renderReader();
    }
  }

  function jumpTo(i) {
    const f = currentFile();
    if (!f) return;
    const b = (f.bookmarks || [])[i];
    if (!b) return;
    showTab("library");
    const article = $("md-view");
    const heads = article.querySelectorAll("h1,h2,h3,h4,h5,h6");
    const hit = [...heads].find((h) => h.textContent.trim() === b.title) || heads[i];
    if (hit) hit.scrollIntoView({ block: "start", behavior: "smooth" });
  }

  async function ingest(file) {
    const jobs = $("jobs");
    const row = document.createElement("div");
    row.className = "job";
    row.textContent = "Reading " + file.name + "…";
    jobs.prepend(row);
    try {
      const buf = await file.arrayBuffer();
      const ext = file.name.split(".").pop().toLowerCase();
      let rec;
      if (ext === "pdf") rec = await convertPdf(buf, file.name, (msg) => { row.textContent = msg; });
      else if (ext === "docx") rec = await convertDocx(buf, file.name);
      else if (ext === "md" || ext === "markdown" || ext === "txt") {
        const text = new TextDecoder().decode(buf);
        rec = { markdown: text, bookmarks: bookmarksFrom(text, []), name: file.name };
      } else throw new Error("Use a PDF, Word, or Markdown file. The Mac app reads more types.");
      const title = rec.name.replace(/\.[^.]+$/, "");
      const item = {
        id: uid(),
        title,
        kind: "MARKDOWN",
        markdown: rec.markdown,
        bookmarks: rec.bookmarks,
        at: Date.now(),
      };
      await dbPut(item);
      state.files.unshift(item);
      state.current = item.id;
      if (rec.scan) {
        row.className = "job notice";
        row.innerHTML =
          "<span>This PDF is a scan — a photograph of the page. This browser preview does not include OCR. Use the Mac app for scans, tables, and figures.</span>" +
          '<a href="https://github.com/Burbank/yourMark" target="_blank" rel="noopener">Mac app on GitHub</a>';
        showTab("library");
        return;
      }
      row.innerHTML = `<span>✓ ${escapeHtml(title)}</span><button data-open="${item.id}">Open</button>`;
      showTab("library");
    } catch (err) {
      row.className = "job notice";
      row.innerHTML =
        "<span>Could not read this file here. This site is a browser preview and does not include OCR. The Mac app is better for scans, tables, and figures.</span>" +
        '<a href="https://github.com/Burbank/yourMark" target="_blank" rel="noopener">Mac app on GitHub</a>';
    }
  }

  function chapterText() {
    const f = currentFile();
    if (!f) return "";
    const q = $("ask-q").value;
    const parts = f.markdown.split(/^#{1,6} /m);
    if (parts.length < 3) return f.markdown.slice(0, 12000);
    const heads = [...$("md-view").querySelectorAll("h1,h2,h3")];
    const on = heads[0] ? heads[0].textContent : "";
    const block = f.markdown.split("\n#").find((p, i) => i && p.toLowerCase().includes((on || "").toLowerCase().slice(0, 24)));
    return (block || f.markdown).slice(0, 12000) + (q ? "" : "");
  }

  function extractive(chapter, question) {
    const words = question.toLowerCase().split(/\W+/).filter((w) => w.length > 3);
    const sents = chapter.replace(/\n+/g, " ").split(/(?<=[.?!])\s+/);
    const scored = sents
      .map((s) => ({ s, n: words.filter((w) => s.toLowerCase().includes(w)).length }))
      .filter((x) => x.n)
      .sort((a, b) => b.n - a.n)
      .slice(0, 3)
      .map((x) => x.s.trim());
    if (/\b(AND|OR|NOT)\b/.test(question) && !booleanHit(chapter, question)) {
      return "That chapter does not say. AND, OR, and NOT must be capitals, in the same sentence.";
    }
    if (!scored.length) return "That chapter does not say. Try another heading, or the Mac app with your own key.";
    return scored.join(" ");
  }

  async function ask() {
    const q = $("ask-q").value.trim();
    if (!q) return;
    state.lastAsk = q;
    state.askHistory = [{ q, at: Date.now() }, ...state.askHistory.filter((h) => h.q !== q)].slice(0, 20);
    sessionStorage.setItem("yourmark-asks", JSON.stringify(state.askHistory));
    const chapter = chapterText();
    const local = extractive(chapter, q);
    if (state.settings.key) {
      showAskAnswer(q, "Trying your key…");
      try {
        const url =
          state.settings.provider === "xai"
            ? "https://api.x.ai/v1/chat/completions"
            : "https://api.openai.com/v1/chat/completions";
        const r = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + state.settings.key },
          body: JSON.stringify({
            model: state.settings.provider === "xai" ? "grok-3" : "gpt-4o-mini",
            max_tokens: 400,
            messages: [
              { role: "system", content: "Answer only from the chapter. If it is silent, say so." },
              { role: "user", content: chapter.slice(0, 8000) + "\n\nQuestion: " + q },
            ],
          }),
        });
        if (!r.ok) throw new Error("HTTP " + r.status);
        const j = await r.json();
        showAskAnswer(q, (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || local);
        return;
      } catch {
        showAskAnswer(q, local + " (This browser could not call the model. The Mac app can.)");
        return;
      }
    }
    showAskAnswer(q, local);
  }

  function fillSettings() {
    $("opt-chrome").checked = !!state.settings.stripChrome;
    if ($("opt-lang")) $("opt-lang").value = state.settings.lang || "en";
    $("opt-font").value = state.settings.font;
    $("opt-provider").value = state.settings.provider;
    $("opt-key").value = state.settings.key ? "••••••••" : "";
    if ($("opt-gkey")) $("opt-gkey").value = state.settings.googleKey ? "••••••••" : "";
    if ($("opt-tr-engine")) $("opt-tr-engine").value = state.settings.trEngine || "preview";
    $("font-size").value = state.settings.fontSize;
    if ($("fig-size")) $("fig-size").value = state.settings.figSize || 320;
    document.documentElement.style.setProperty("--fig-max", (state.settings.figSize || 320) + "px");
    $("ask-model").textContent = state.settings.key ? "Your key · this tab" : "Ask this chapter · stays in this tab";
  }

  function editorUrl() {
    return /Mac|iPhone/.test(navigator.platform || navigator.userAgent)
      ? "https://github.com/MarkEdit-app/MarkEdit"
      : "https://github.com/marktext/marktext/releases/latest";
  }

  document.querySelectorAll("[data-tab]").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));
  $("theme-seg").addEventListener("click", (e) => {
    const t = e.target.dataset.theme;
    if (!t) return;
    state.settings.theme = t;
    saveSettings();
    applyTheme();
  });
  $("btn-help").onclick = () => ($("help").hidden = false);
  $("help-close").onclick = () => ($("help").hidden = true);
  $("help").addEventListener("click", (e) => {
    if (e.target.id === "help") $("help").hidden = true;
  });
  $("cards").addEventListener("click", (e) => {
    const del = e.target.dataset.del;
    if (del) {
      e.stopPropagation();
      dbDel(del).then(() => {
        state.files = state.files.filter((f) => f.id !== del);
        if (state.current === del) state.current = GUIDE_ID;
        renderCards();
        renderToc();
        renderReader();
      });
      return;
    }
    const id = e.target.closest("[data-id]") && e.target.closest("[data-id]").dataset.id;
    if (!id) return;
    state.current = id;
    state.tr.text = "";
    showTab("library");
  });
  $("toc").addEventListener("click", (e) => {
    if (e.target.dataset.jump != null) jumpTo(+e.target.dataset.jump);
  });
  $("btn-rendered").onclick = () => {
    state.rendered = true;
    renderReader();
  };
  $("btn-source").onclick = () => {
    state.rendered = false;
    renderReader();
  };
  $("font-size").oninput = (e) => {
    state.settings.fontSize = +e.target.value;
    saveSettings();
    renderReader();
  };
  if ($("btn-copy")) {
    $("btn-copy").onclick = async () => {
      const f = currentFile();
      if (!f) return;
      try {
        await navigator.clipboard.writeText(f.markdown);
        $("btn-copy").textContent = "Copied";
        setTimeout(() => applyLang(), 1200);
      } catch {
        $("btn-copy").textContent = "Copy failed";
      }
    };
  }
  $("btn-download").onclick = () => {
    const f = currentFile();
    if (!f) return;
    const blob = new Blob([f.markdown], { type: "text/markdown" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = (f.title || "yourMark") + ".md";
    a.click();
  };
  $("btn-ask").onclick = ask;
  $("ask-q").addEventListener("keydown", (e) => {
    if (e.key === "Enter") ask();
  });
  $("btn-choose").onclick = () => $("file-input").click();
  $("file-input").onchange = () => {
    [...$("file-input").files].forEach(ingest);
    $("file-input").value = "";
  };
  $("jobs").addEventListener("click", (e) => {
    if (e.target.dataset.open) {
      state.current = e.target.dataset.open;
      showTab("library");
    }
  });

  const drop = $("drop");
  const over = (e) => {
    e.preventDefault();
    drop.classList.add("hot");
  };
  drop.addEventListener("dragover", over);
  drop.addEventListener("dragleave", () => drop.classList.remove("hot"));
  drop.addEventListener("drop", (e) => {
    e.preventDefault();
    drop.classList.remove("hot");
    [...e.dataTransfer.files].forEach(ingest);
  });
  window.addEventListener("dragover", (e) => e.preventDefault());
  window.addEventListener("drop", (e) => {
    if (e.target.closest("#drop")) return;
    e.preventDefault();
    if (e.dataTransfer.files.length) {
      showTab("convert");
      [...e.dataTransfer.files].forEach(ingest);
    }
  });

  $("opt-chrome").onchange = (e) => {
    state.settings.stripChrome = e.target.checked;
    saveSettings();
  };
  $("opt-font").onchange = (e) => {
    state.settings.font = e.target.value;
    saveSettings();
    renderReader();
  };
  $("opt-provider").onchange = (e) => {
    state.settings.provider = e.target.value;
    saveSettings();
  };
  $("btn-lock-key").onclick = () => {
    const v = $("opt-key").value.trim();
    if (v && v !== "••••••••") state.settings.key = v;
    saveSettings();
    fillSettings();
    $("key-status").textContent = state.settings.key
      ? "Key saved in this tab. Press Test key. Browsers often block the call; the Mac app does not."
      : "No key stored.";
  };
  $("btn-test-key").onclick = async () => {
    if (!state.settings.key) {
      $("key-status").textContent = "Paste a key, then Enter.";
      return;
    }
    $("key-status").textContent = "Testing…";
    try {
      const url =
        state.settings.provider === "xai"
          ? "https://api.x.ai/v1/models"
          : "https://api.openai.com/v1/models";
      const r = await fetch(url, { headers: { Authorization: "Bearer " + state.settings.key } });
      $("key-status").textContent = r.ok
        ? "The key answered. Ask a chapter from the library."
        : "The key was refused (" + r.status + "). Check it starts with sk- or xai- and matches the provider.";
    } catch {
      $("key-status").textContent =
        "This browser blocked the test (CORS). The key is stored here. The Mac app can use it for real Ask.";
    }
  };
  $("btn-get-editor").onclick = () => window.open(editorUrl(), "_blank");

  $("btn-hunter").onclick = () => {
    state.hunterOn = !state.hunterOn;
    $("btn-hunter").classList.toggle("on", state.hunterOn);
  };
  $("btn-forage").onclick = async () => {
    const item = await forageFile();
    state.current = item.id;
    showTab("library");
  };
  $("btn-hide-lib").onclick = () => {
    state.hideLib = !state.hideLib;
    $("view-library").classList.toggle("hide-lib", state.hideLib);
    $("btn-hide-lib").textContent = state.hideLib ? "››" : "‹‹";
  };
  $("lib-search").addEventListener("input", () => renderCards());
  $("find-q").addEventListener("input", () => renderReader());
  $("btn-add-forage").onclick = () => {
    const body = ($("ask-ans-body") && $("ask-ans-body").textContent) || state.lastAnswer;
    addToForage((body || state.lastAsk) + (state.lastAsk ? "\n\n_Question: " + state.lastAsk + "_" : ""), "Ask");
  };
  $("btn-ask-hist").onclick = () => {
    const box = $("ask-hist");
    box.hidden = !box.hidden;
    box.innerHTML = state.askHistory.length
      ? state.askHistory.map((h) => `<button type="button" data-replay="${escapeHtml(h.q)}">${escapeHtml(h.q)}</button>`).join("")
      : "<p class='muted'>No recent Asks in this tab.</p>";
  };
  $("ask-hist").addEventListener("click", (e) => {
    const q = e.target.dataset.replay;
    if (!q) return;
    $("ask-q").value = q;
    $("ask-hist").hidden = true;
    ask();
  });
  $("opt-lang").onchange = (e) => {
    state.settings.lang = e.target.value;
    saveSettings();
    applyLang();
  };
  $("btn-clear-lib").onclick = async () => {
    if (!state.files.length) return;
    if (!confirm("Remove converted files from this browser?")) return;
    for (const f of [...state.files]) await dbDel(f.id);
    state.files = [];
    state.current = GUIDE_ID;
    showTab("library");
  };
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      $("help").hidden = true;
      if ($("ask-hist")) $("ask-hist").hidden = true;
      hideFig();
      return;
    }
    if ((e.key === "/" || (e.key === "f" && (e.metaKey || e.ctrlKey))) && e.target && e.target.tagName !== "INPUT" && e.target.tagName !== "TEXTAREA") {
      e.preventDefault();
      $("find-q").focus();
      return;
    }
    if (e.key === "k" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      $("ask-q").focus();
      return;
    }
    if (e.key !== "Enter" || !state.hunterOn) return;
    if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.isContentEditable)) return;
    const sel = String(window.getSelection() || "").trim();
    if (!sel) return;
    e.preventDefault();
    addToForage(sel);
  });

  if ($("btn-tr")) $("btn-tr").onclick = runTranslate;
  if ($("btn-tr-save")) $("btn-tr-save").onclick = saveTranslation;
  document.querySelectorAll("[data-tr-mode]").forEach((b) => {
    b.onclick = () => {
      state.tr.mode = b.dataset.trMode;
      renderReader();
    };
  });
  if ($("tr-from")) $("tr-from").onchange = (e) => { state.tr.from = e.target.value; };
  if ($("tr-to")) $("tr-to").onchange = (e) => { state.tr.to = e.target.value; };
  if ($("tr-sync")) {
    $("tr-sync").onchange = (e) => {
      const left = $("md-left");
      const right = $("md-right");
      if (!left || !right) return;
      const sync = (a, b) => {
        b.scrollTop = a.scrollTop;
      };
      left.onscroll = e.target.checked ? () => sync(left, right) : null;
      right.onscroll = e.target.checked ? () => sync(right, left) : null;
    };
  }
  if ($("fig-size")) {
    $("fig-size").oninput = (e) => {
      state.settings.figSize = +e.target.value;
      document.documentElement.style.setProperty("--fig-max", state.settings.figSize + "px");
      saveSettings();
    };
  }
  if ($("opt-tr-engine")) {
    $("opt-tr-engine").onchange = (e) => {
      state.settings.trEngine = e.target.value;
      saveSettings();
    };
  }
  if ($("btn-lock-gkey")) {
    $("btn-lock-gkey").onclick = () => {
      const v = $("opt-gkey").value.trim();
      if (v && v !== "••••••••") state.settings.googleKey = v;
      saveSettings();
      fillSettings();
      $("gkey-status").textContent = state.settings.googleKey
        ? "Google key saved in this tab. Set Engine to Google Translate."
        : "No Google key stored.";
    };
  }
  if ($("ask-ans-close")) $("ask-ans-close").onclick = () => { $("ask-ans").hidden = true; };
  function hideHero() {
    state.settings.hideHero = true;
    saveSettings();
    applyHero();
  }
  if ($("hero-close")) $("hero-close").onclick = hideHero;
  if ($("btn-try")) $("btn-try").onclick = hideHero;
  if ($("btn-open-demo")) {
    $("btn-open-demo").onclick = () => {
      state.current = DEMO_ID;
      showTab("library");
    };
  }

  applyTheme();
  fillSettings();
  fillTrLangs();
  applyLang();
  applyHero();
  dbAll()
    .then((rows) => {
      state.files = (rows || []).sort((a, b) => (b.at || 0) - (a.at || 0));
      showTab("library");
    })
    .catch(() => showTab("library"));
})();
