(() => {
  const languageButton = document.getElementById("lang-toggle");
  const translations = [
    ...Array.from(document.querySelectorAll("[data-en]"), (element) => ({
      element,
      zh: element.textContent,
      en: element.dataset.en,
    })),
    ...["aria-label", "content"].flatMap((attribute) =>
      Array.from(document.querySelectorAll(`[data-en-${attribute}]`), (element) => ({
        element,
        attribute,
        zh: element.getAttribute(attribute),
        en: element.getAttribute(`data-en-${attribute}`),
      })),
    ),
  ];

  let language = "zh";
  try {
    if (localStorage.getItem("ks-lang") === "en") language = "en";
  } catch {
    // The language switch still works for the current page without storage.
  }

  function applyLanguage() {
    document.documentElement.lang = language === "en" ? "en" : "zh-CN";
    for (const { element, attribute, ...translation } of translations) {
      if (attribute) {
        element.setAttribute(attribute, translation[language]);
      } else {
        element.textContent = translation[language];
      }
    }
    languageButton.textContent = language === "en" ? "中文" : "EN";
    languageButton.lang = language === "en" ? "zh-CN" : "en";
    languageButton.setAttribute("aria-label", language === "en" ? "切换到中文" : "Switch to English");
  }

  applyLanguage();
  languageButton.hidden = false;
  languageButton.addEventListener("click", () => {
    language = language === "en" ? "zh" : "en";
    applyLanguage();
    try {
      localStorage.setItem("ks-lang", language);
    } catch {
      // Storage may be unavailable in a private browser context.
    }
  });

  const tabList = document.querySelector(".tech-tabs");
  const tabs = Array.from(tabList.querySelectorAll('[role="tab"]'));
  const panels = tabs.map((tab) => document.getElementById(tab.getAttribute("aria-controls")));
  let selectedIndex = 0;

  function selectTechnology(index, animate) {
    selectedIndex = index;
    tabs.forEach((tab, position) => {
      const selected = index === position;
      tab.setAttribute("aria-selected", String(selected));
      tab.tabIndex = selected ? 0 : -1;
      panels[position].hidden = !selected;
      panels[position].classList.toggle("is-tracing", selected && animate);
    });
  }

  tabs.forEach((tab, index) => {
    const panel = panels[index];
    panel.setAttribute("role", "tabpanel");
    panel.setAttribute("aria-labelledby", tab.id);
    panel.tabIndex = 0;
    tab.addEventListener("click", () => {
      if (selectedIndex !== index) selectTechnology(index, true);
    });
  });

  tabList.addEventListener("keydown", (event) => {
    let index;
    switch (event.key) {
      case "ArrowLeft":
        index = (selectedIndex - 1 + tabs.length) % tabs.length;
        break;
      case "ArrowRight":
        index = (selectedIndex + 1) % tabs.length;
        break;
      case "Home":
        index = 0;
        break;
      case "End":
        index = tabs.length - 1;
        break;
      default:
        return;
    }
    event.preventDefault();
    selectTechnology(index, true);
    tabs[index].focus();
  });

  selectTechnology(0, false);
  tabList.hidden = false;
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      panels[selectedIndex].classList.add("is-tracing");
      observer.disconnect();
    }, { threshold: 0.16 });
    observer.observe(document.querySelector(".tech-panels"));
  }

  const copyFeedback = document.getElementById("copy-feedback");
  for (const button of document.querySelectorAll("[data-copy]")) {
    const code = document.getElementById(button.dataset.copy);
    const label = button.querySelector("span");
    let resetLabel;
    button.hidden = false;
    button.addEventListener("click", async () => {
      const english = () => language === "en";
      let result;
      try {
        await navigator.clipboard.writeText(code.textContent);
        result = english() ? "Copied" : "已复制";
      } catch {
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        result = english() ? "Selected" : "已选中";
      }
      label.textContent = result;
      copyFeedback.textContent = result;
      clearTimeout(resetLabel);
      resetLabel = setTimeout(() => {
        label.textContent = english() ? "Copy" : "复制";
        if (copyFeedback.textContent === result) copyFeedback.textContent = "";
      }, 1800);
    });
  }
})();
