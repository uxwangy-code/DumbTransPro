/* Shared 中 / EN language toggle for all DumbTrans Pro pages.
 *
 * Each translatable element carries its English in a data-en attribute; its
 * default (visible, no-JS, SEO) content is Chinese. On load this script:
 *   - reuses an existing .lang-toggle (the landing page menu bar) or injects a
 *     floating one (the legal pages), so every page gets a switcher for free;
 *   - picks the initial language: saved choice > system language > Chinese;
 *   - persists the choice in localStorage, shared across all pages on the site,
 *     so secondary pages follow whatever the visitor last chose.
 */
(function () {
  // 1. styles for the auto-injected floating toggle (legal pages). Scoped to
  //    --floating so it never touches the landing page's own .lang-toggle.
  var style = document.createElement("style");
  style.textContent =
    ".lang-toggle--floating{position:fixed;top:14px;right:16px;z-index:50;display:inline-flex;" +
    "border:1px solid #E4E4E9;border-radius:7px;overflow:hidden;background:#fff;" +
    "box-shadow:0 1px 3px rgba(0,0,0,0.08);}" +
    ".lang-toggle--floating button{font-family:inherit;font-size:12px;padding:3px 10px;" +
    "background:#fff;border:none;color:#6E6E73;cursor:pointer;line-height:1.5;}" +
    ".lang-toggle--floating button+button{border-left:1px solid #E4E4E9;}" +
    ".lang-toggle--floating button.active{background:#1D1D1F;color:#fff;}";
  document.head.appendChild(style);

  // 2. reuse an existing toggle, or create a floating one
  var toggle = document.querySelector(".lang-toggle");
  if (!toggle) {
    toggle = document.createElement("div");
    toggle.className = "lang-toggle lang-toggle--floating";
    toggle.setAttribute("role", "group");
    toggle.setAttribute("aria-label", "Language / 语言");
    toggle.innerHTML =
      '<button type="button" data-lang="zh">中</button>' +
      '<button type="button" data-lang="en">EN</button>';
    document.body.appendChild(toggle);
  }
  var btns = toggle.querySelectorAll("button");

  // 3. capture the Chinese default of every translatable node
  var nodes = document.querySelectorAll("[data-en]");
  nodes.forEach(function (el) { el.setAttribute("data-zh", el.innerHTML); });

  function apply(lang, persist) {
    nodes.forEach(function (el) {
      el.innerHTML = (lang === "en") ? el.getAttribute("data-en") : el.getAttribute("data-zh");
    });
    document.documentElement.lang = (lang === "en") ? "en" : "zh-Hans";
    btns.forEach(function (b) {
      b.classList.toggle("active", b.getAttribute("data-lang") === lang);
    });
    if (persist) { try { localStorage.setItem("dtp-lang", lang); } catch (e) {} }
  }

  btns.forEach(function (b) {
    b.addEventListener("click", function () { apply(b.getAttribute("data-lang"), true); });
  });

  // 4. initial language: saved choice > system language > Chinese default
  var saved = null;
  try { saved = localStorage.getItem("dtp-lang"); } catch (e) {}
  var system = ((navigator.language || "").toLowerCase().indexOf("zh") === 0) ? "zh" : "en";
  apply(saved || system, false);
})();
