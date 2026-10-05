(function () {
  const data = {
    groups: [
      { name: "Pessoal", folders: [
        { name: "dockfolders", openers: ["vscode", "terminal", "finder", "xcode"], cmd: "claude" },
        { name: "receitas-app", openers: ["xcode", "terminal", "finder"], file: "Receitas.xcworkspace" },
        { name: "portfolio", openers: ["vscode", "terminal", "finder"], cmd: "npm run dev" },
        { name: "weather-kit", openers: ["xcode", "terminal", "finder"], file: "WeatherKit.xcodeproj" },
        { name: "prototipo-antigo", openers: ["vscode", "finder"], missing: true },
      ]},
      { name: "Acme (Cliente)", folders: [
        { name: "acme-ios", openers: ["xcode", "terminal", "finder"], file: "Acme.xcworkspace" },
        { name: "acme-android", openers: ["studio", "terminal", "finder"] },
        { name: "acme-api", openers: ["vscode", "terminal", "finder"], cmd: "npm run dev" },
        { name: "acme-web", openers: ["vscode", "terminal", "finder"] },
        { name: "acme-docs", openers: ["finder", "vscode"] },
      ]},
      { name: "Nimbus", folders: [
        { name: "nimbus-ios", openers: ["xcode", "terminal", "finder"] },
        { name: "nimbus-android", openers: ["studio", "terminal", "finder"] },
        { name: "nimbus-design-system", openers: ["vscode", "finder"] },
        { name: "nimbus-api", openers: ["vscode", "terminal", "finder"] },
        { name: "nimbus-infra", openers: ["terminal", "finder"] },
        { name: "nimbus-scripts", openers: ["terminal", "finder"] },
      ]},
      { name: "Orbita RN", folders: [
        { name: "orbita-app", openers: ["vscode", "terminal", "finder"], cmd: "npx expo start" },
        { name: "orbita-ios", openers: ["xcode", "finder"] },
        { name: "orbita-android", openers: ["studio", "finder"] },
      ]},
      { name: "Estudos", folders: [
        { name: "swiftui-lab", openers: ["xcode", "finder"] },
        { name: "rust-book", openers: ["vscode", "terminal"] },
      ]},
    ],
  };
  const appName = { finder: "Finder", terminal: "Terminal", xcode: "Xcode", vscode: "VS Code", studio: "Android Studio" };
  const sym = (key) => key === "finder" ? "i-folder" : "a-" + key;
  let openGroup = 0;
  let activeRow = null;

  const desk = document.getElementById("desk");
  const balloon = document.getElementById("balloon");
  const content = document.getElementById("balloonContent");
  const popover = document.getElementById("popover");
  const status = document.getElementById("status");
  const dockBtn = document.getElementById("dockBtn");
  const stage = balloon.parentElement;
  let statusTimer;

  const icon = (id, cls) => `<svg class="${cls}" aria-hidden="true"><use href="#${id}"/></svg>`;
  const go = icon("g-go", "go");

  function say(text) {
    status.textContent = text;
    clearTimeout(statusTimer);
    statusTimer = setTimeout(() => { status.textContent = ""; }, 2600);
  }

  function openWith(f, key) {
    if (f.missing) return;
    let what = f.name;
    if (key === "xcode" && f.file) what = f.file;
    let text = `Abrindo ${what} no ${appName[key]}`;
    if (key === "terminal" && f.cmd) text = `Terminal em ${f.name} → ${f.cmd}`;
    say(text);
  }

  function folderRow(f) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "row folder-row" + (f.missing ? " missing" : "");
    b.innerHTML = `${icon(sym(f.openers[0]), "app")}<span class="name">${f.name}</span>${go}`;
    b.title = f.missing ? "Pasta não encontrada" : `Abrir com ${appName[f.openers[0]]}`;
    b.addEventListener("mouseenter", () => showPopover(f, b));
    b.addEventListener("focus", () => showPopover(f, b));
    b.addEventListener("click", () => { openWith(f, f.openers[0]); hidePopover(); });
    return b;
  }

  function render() {
    hidePopover();
    content.innerHTML = "";
    const frag = document.createDocumentFragment();
    data.groups.forEach((g, i) => {
      const h = document.createElement("button");
      h.type = "button";
      h.className = "row group-head";
      h.setAttribute("aria-expanded", String(openGroup === i));
      h.innerHTML = `<svg class="chev" viewBox="0 0 14 14" aria-hidden="true"><path d="M5 2.5L9.5 7 5 11.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg><span class="name">${g.name}</span><span class="count">${g.folders.length}</span><span class="all" title="Abrir tudo">${icon("g-all", "")}</span>`;
      h.addEventListener("mouseenter", hidePopover);
      h.addEventListener("click", (e) => {
        if (e.target.closest(".all")) {
          say(`Abrindo ${g.folders.filter((f) => !f.missing).length} pastas de ${g.name}`);
          return;
        }
        openGroup = openGroup === i ? -1 : i; render();
      });
      frag.appendChild(h);
      if (openGroup === i) g.folders.forEach((f) => frag.appendChild(folderRow(f)));
    });
    const foot = document.createElement("div");
    foot.className = "foot";
    foot.innerHTML = `<span title="Adicionar pasta ou grupo">${icon("g-plus", "")}</span><span title="Opções">${icon("g-gear", "")}</span>`;
    frag.appendChild(foot);
    content.appendChild(frag);
  }

  function showPopover(f, row) {
    if (f.missing || desk.classList.contains("sharing")) { hidePopover(); return; }
    if (activeRow && activeRow !== row) activeRow.classList.remove("active");
    activeRow = row;
    row.classList.add("active");
    popover.innerHTML = "";
    f.openers.forEach((key, i) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "opener" + (i === 0 ? " primary" : "");
      b.title = appName[key] + (i === 0 ? " (principal)" : "");
      b.setAttribute("aria-label", `Abrir ${f.name} com ${appName[key]}`);
      b.innerHTML = `<svg aria-hidden="true"><use href="#${sym(key)}"/></svg>`;
      b.addEventListener("click", () => { openWith(f, key); hidePopover(); });
      popover.appendChild(b);
    });
    const add = document.createElement("span");
    add.className = "opener add";
    add.setAttribute("aria-hidden", "true");
    add.innerHTML = icon("g-plus", "");
    popover.appendChild(add);
    popover.hidden = false;

    const s = stage.getBoundingClientRect();
    const r = row.getBoundingClientRect();
    const bw = balloon.getBoundingClientRect();
    const pw = popover.offsetWidth, ph = popover.offsetHeight;
    const roomRight = desk.getBoundingClientRect().right - bw.right - 12;
    popover.classList.toggle("below", roomRight < pw);
    if (roomRight >= pw) {
      popover.style.left = (bw.right - s.left + 14) + "px";
      popover.style.top = (r.top - s.top + r.height / 2 - ph / 2) + "px";
    } else {
      popover.style.left = Math.max(0, r.right - s.left - pw) + "px";
      popover.style.top = (r.bottom - s.top + 4) + "px";
    }
  }
  function placeArrow() {
    const b = balloon.getBoundingClientRect();
    const d = dockBtn.getBoundingClientRect();
    const x = Math.min(Math.max(d.left + d.width / 2 - b.left, 20), b.width - 20);
    balloon.style.setProperty("--arrow-x", x + "px");
  }
  function hidePopover() {
    popover.hidden = true;
    if (activeRow) activeRow.classList.remove("active");
    activeRow = null;
  }

  balloon.addEventListener("mouseleave", (e) => { if (!popover.contains(e.relatedTarget)) hidePopover(); });
  popover.addEventListener("mouseleave", (e) => { if (!balloon.contains(e.relatedTarget)) hidePopover(); });

  dockBtn.addEventListener("click", () => {
    const closed = balloon.classList.toggle("closed");
    dockBtn.setAttribute("aria-expanded", String(!closed));
    if (closed) hidePopover(); else render();
  });
  desk.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !balloon.classList.contains("closed")) {
      balloon.classList.add("closed"); dockBtn.setAttribute("aria-expanded", "false"); hidePopover(); dockBtn.focus();
    }
  });

  const shareToggle = document.getElementById("shareToggle");
  const shareNote = document.getElementById("shareNote");
  shareToggle.addEventListener("click", () => {
    const on = shareToggle.getAttribute("aria-pressed") !== "true";
    shareToggle.setAttribute("aria-pressed", String(on));
    desk.classList.toggle("sharing", on);
    shareNote.hidden = !on || balloon.classList.contains("closed");
    hidePopover();
  });

  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const text = document.getElementById(btn.dataset.copy).textContent;
      const done = () => { btn.textContent = "Copiado"; setTimeout(() => { btn.textContent = "Copiar"; }, 1600); };
      try {
        navigator.clipboard.writeText(text).then(done, () => selectText(btn.dataset.copy));
      } catch (e) { selectText(btn.dataset.copy); }
    });
  });
  function selectText(id) {
    const r = document.createRange();
    r.selectNodeContents(document.getElementById(id));
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
  }

  render();
  requestAnimationFrame(() => {
    placeArrow();
    const first = content.querySelector(".folder-row");
    if (first) showPopover(data.groups[0].folders[0], first);
  });
  window.addEventListener("resize", () => {
    placeArrow();
    if (activeRow && !popover.hidden) {
      const f = data.groups.flatMap((g) => g.folders).find((x) => x.name === activeRow.querySelector(".name").textContent);
      if (f) showPopover(f, activeRow);
    }
  });
})();
