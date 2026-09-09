/* simpler yourMark — files stay in this tab */
(() => {
  const GUIDE_ID = "guide";
  const GUIDE_CARDS = [
    ["Browser preview", "This site is a preview. Files stay in this tab. Nothing is uploaded. The browser version does not include OCR."],
    ["Mac app", "Better for PDFs with graphics — OCR and layout. Scans, tables, and figures stay intact there."],
    ["Convert", "Drop a PDF that already has selectable text. A scan (a photograph of the page) gets a short note. Use the Mac app for that."],
    ["Library", "Cards on the left. Click to open. The × removes a file from this browser only."],
    ["Bookmarks", "The middle pane is the PDF outline when the file has one, otherwise headings. Click to jump."],
    ["Ask", "The answer is taken from the open chapter, in this tab. A real model needs the Mac app."],
    ["Edit", "Download, then open in MarkEdit (Mac) or MarkText (Windows). Both are free."],
    ["Themes", "Bright, Dim, or System in the header. Font and size are in Settings."],
  ];

  const GUIDE = `# Getting started with yourMark

This site is a **browser preview**. The browser version does **not** include OCR.

The [Mac app](https://github.com/Burbank/yourMark/releases/latest) is better for PDFs with graphics — OCR and layout. Scans, tables, and figures stay intact there.
`;

  pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";

  const $ = (id) => document.getElementById(id);
  const state = {
    tab: "library",
    files: [],
    current: GUIDE_ID,
    rendered: true,
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
        },
        JSON.parse(localStorage.getItem("yourmark-settings") || "{}")
      );
    } catch {
      return { theme: "bright", font: "Atkinson Hyperlegible", fontSize: 18, stripChrome: true, provider: "openai", key: "" };
    }
  }
  function saveSettings() {
    const { key, ...rest } = state.settings;
    localStorage.setItem("yourmark-settings", JSON.stringify({ ...rest, key: key ? "set" : "" }));
    sessionStorage.setItem("yourmark-key", state.settings.key || "");
  }
  if (sessionStorage.getItem("yourmark-key")) {
    state.settings.key = sessionStorage.getItem("yourmark-key");
  } else if (state.settings.key === "set") {
    state.settings.key = "";
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
      "[Download the Mac app](https://github.com/Burbank/yourMark/releases/latest)",
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
    const pictures = [];
    for (let i = 1; i <= n; i++) {
      pictures.push([]);
    }
    const chrome = state.settings.stripChrome ? chromeSet(pages) : new Set();
    const parts = [];
    pages.forEach((lines, i) => {
      const body = (lines || [])
        .filter((l) => !chrome.has(norm(l)))
        .filter((l) => !/^\s*\d+\s*$/.test(l))
        .map(headingize);
      if (!body.length) return;
      parts.push("<!-- page " + (i + 1) + " -->", "");
      parts.push.apply(parts, body.concat([""]));
    });
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
      .replace(/&/g, "&")
      .replace(/</g, "<")
      .replace(/>/g, ">")
      .replace(/&nbsp;/g, " ");
    const md = html.replace(/\n{3,}/g, "\n\n").trim() || "_Empty Word file._";
    return { markdown: md, bookmarks: bookmarksFrom(md, []), name };
  }

  function uid() {
    return "f" + Math.random().toString(36).slice(2, 10);
  }

  function currentFile() {
    if (state.current === GUIDE_ID) {
      return { id: GUIDE_ID, title: "Getting started with yourMark", kind: "GUIDE", markdown: GUIDE, bookmarks: bookmarksFrom(GUIDE, []) };
    }
    return state.files.find((f) => f.id === state.current) || null;
  }

  function renderCards() {
    const box = $("cards");
    const items = [
      { id: GUIDE_ID, title: "Getting started with yourMark", kind: "GUIDE" },
      ...state.files.map((f) => ({ id: f.id, title: f.title, kind: "MARKDOWN" })),
    ];
    box.innerHTML = items
      .map(
        (it) => `<div class="card ${it.id === state.current ? "on" : ""}" data-id="${it.id}">
        ${it.id === GUIDE_ID ? "" : `<button class="del" data-del="${it.id}" title="Remove">×</button>`}
        <small>${it.kind}</small>${escapeHtml(it.title)}</div>`
      )
      .join("");
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

  function renderReader() {
    const f = currentFile();
    $("reader-title").textContent = f ? f.title : "";
    $("md-view").style.fontFamily = state.settings.font;
    $("md-view").style.fontSize = state.settings.fontSize + "px";
    $("md-src").style.fontSize = Math.max(13, state.settings.fontSize - 2) + "px";
    if (!f) {
      $("md-view").innerHTML = "";
      $("md-src").textContent = "";
      return;
    }
    $("md-src").textContent = f.markdown;
    if (f.id === GUIDE_ID && state.rendered) {
      $("md-view").innerHTML = GUIDE_CARDS.map(
        ([h, p]) => `<article><h3>${h}</h3><p>${p}</p></article>`
      ).join("");
      $("md-view").classList.add("help-grid");
    } else {
      $("md-view").classList.remove("help-grid");
      const html = mdToHtml(f.markdown);
      $("md-view").innerHTML = DOMPurify.sanitize(html, { ADD_TAGS: ["img"], ADD_ATTR: ["src", "alt"] });
    }
    $("md-view").hidden = !state.rendered;
    $("md-src").hidden = state.rendered;
    $("btn-rendered").classList.toggle("on", state.rendered);
    $("btn-source").classList.toggle("on", !state.rendered);
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
      else if (ext === "md" || ext === "txt") {
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
          '<a href="https://github.com/Burbank/yourMark/releases/latest" target="_blank" rel="noopener">Get the Mac app</a>';
        showTab("library");
        return;
      }
      row.innerHTML = `<span>✓ ${escapeHtml(title)}</span><button data-open="${item.id}">Open</button>`;
      showTab("library");
    } catch (err) {
      row.className = "job notice";
      row.innerHTML =
        "<span>Could not read this file here. This site is a browser preview and does not include OCR. The Mac app is better for scans, tables, and figures.</span>" +
        '<a href="https://github.com/Burbank/yourMark/releases/latest" target="_blank" rel="noopener">Get the Mac app</a>';
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
    if (!scored.length) return "That chapter does not say. Try another heading, or the Mac app with your own key.";
    return scored.join(" ");
  }

  async function ask() {
    const q = $("ask-q").value.trim();
    if (!q) return;
    const chapter = chapterText();
    const local = extractive(chapter, q);
    const box = $("md-view");
    const note = document.createElement("aside");
    note.style.border = "1px solid var(--line)";
    note.style.background = "var(--field)";
    note.style.padding = ".7rem .9rem";
    note.style.borderRadius = "8px";
    note.style.margin = "0 0 1rem";
    if (state.settings.key) {
      note.textContent = "Trying your key…";
      box.prepend(note);
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
        note.textContent = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || local;
        return;
      } catch {
        note.textContent = local + " (This browser could not call the model. The Mac app can.)";
        return;
      }
    }
    note.textContent = local;
    box.prepend(note);
  }

  function fillSettings() {
    $("opt-chrome").checked = !!state.settings.stripChrome;
    $("opt-font").value = state.settings.font;
    $("opt-provider").value = state.settings.provider;
    $("opt-key").value = state.settings.key ? "••••••••" : "";
    $("font-size").value = state.settings.fontSize;
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

  applyTheme();
  fillSettings();
  dbAll()
    .then((rows) => {
      state.files = (rows || []).sort((a, b) => (b.at || 0) - (a.at || 0));
      showTab("library");
    })
    .catch(() => showTab("library"));
})();
