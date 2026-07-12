(function () {
  'use strict';

  // Mobile navigation
  var menuButton = document.querySelector('[data-menu-toggle]');
  var mobileMenu = document.querySelector('[data-mobile-menu]');

  function setMenu(open) {
    if (!menuButton || !mobileMenu) return;
    menuButton.setAttribute('aria-expanded', String(open));
    menuButton.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    mobileMenu.classList.toggle('open', open);
    document.body.classList.toggle('menu-open', open);
  }

  if (menuButton && mobileMenu) {
    menuButton.addEventListener('click', function () {
      setMenu(menuButton.getAttribute('aria-expanded') !== 'true');
    });

    mobileMenu.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () { setMenu(false); });
    });

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') setMenu(false);
    });

    window.addEventListener('resize', function () {
      var breakpoint = document.body.classList.contains('product-page') ? 734 : 1068;
      if (window.innerWidth > breakpoint) setMenu(false);
    });
  }

  // Feature tabs
  document.querySelectorAll('[data-tabs]').forEach(function (root) {
    var buttons = root.querySelectorAll('[data-tab-button]');
    var panels = root.querySelectorAll('[data-tab-panel]');
    var tabList = root.querySelector('.tab-list');

    function activateTab(id, options) {
      options = options || {};
      var activeButton = Array.from(buttons).find(function (button) {
        return button.getAttribute('data-tab-button') === id;
      });
      if (!activeButton) return false;

      var activePanel;
      buttons.forEach(function (button) {
        var isActive = button === activeButton;
        button.classList.toggle('active', isActive);
        button.setAttribute('aria-selected', String(isActive));
        button.tabIndex = isActive ? 0 : -1;
      });
      panels.forEach(function (panel) {
        var isActive = panel.getAttribute('data-tab-panel') === id;
        panel.classList.toggle('active', isActive);
        panel.hidden = !isActive;
        if (isActive) activePanel = panel;
      });

      if (tabList) {
        var left = activeButton.offsetLeft -
          (tabList.clientWidth - activeButton.offsetWidth) / 2;
        tabList.scrollTo({
          left: Math.max(0, left),
          behavior: options.smooth ? 'smooth' : 'auto'
        });
      }

      if (options.updateHash) {
        var hash = id === 'all' ? '#features' : '#' + id;
        window.history.replaceState(null, '', hash);
      }

      if (options.scrollToPanel && activePanel) {
        requestAnimationFrame(function () {
          requestAnimationFrame(function () {
            activePanel.scrollIntoView({ block: 'start', behavior: 'auto' });
          });
        });
      }
      return true;
    }

    function activateFromHash(scrollToPanel) {
      var id = window.location.hash.slice(1);
      if (!id || id === 'features') {
        activateTab('all');
        return;
      }
      activateTab(id, { scrollToPanel: scrollToPanel });
    }

    buttons.forEach(function (button) {
      button.addEventListener('click', function () {
        activateTab(button.getAttribute('data-tab-button'), {
          smooth: true,
          updateHash: true
        });
      });
    });

    window.addEventListener('hashchange', function () {
      activateFromHash(true);
    });
    activateFromHash(Boolean(window.location.hash));
  });

  // Subnav active link on scroll
  var subnav = document.querySelector('.subnav-links');
  if (subnav) {
    var links = subnav.querySelectorAll('a[href^="#"]');
    var sections = Array.from(links).map(function (link) {
      var id = link.getAttribute('href').slice(1);
      return document.getElementById(id);
    }).filter(Boolean);

    function updateActive() {
      var scrollY = window.scrollY + 120;
      var current = sections[0];
      sections.forEach(function (section) {
        if (section.offsetParent !== null && section.offsetTop <= scrollY) current = section;
      });
      links.forEach(function (link) {
        link.classList.toggle('active', link.getAttribute('href') === '#' + current.id);
      });
    }

    window.addEventListener('scroll', updateActive, { passive: true });
    updateActive();
  }

  // Fade-in on scroll
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

  document.querySelectorAll('.fade-in').forEach(function (el) {
    observer.observe(el);
  });
})();
