(function () {
  'use strict';

  // Feature tabs
  document.querySelectorAll('[data-tabs]').forEach(function (root) {
    var buttons = root.querySelectorAll('[data-tab-button]');
    var panels = root.querySelectorAll('[data-tab-panel]');

    buttons.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var id = btn.getAttribute('data-tab-button');
        buttons.forEach(function (b) { b.classList.toggle('active', b === btn); });
        panels.forEach(function (p) {
          p.classList.toggle('active', p.getAttribute('data-tab-panel') === id);
        });
      });
    });
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
        if (section.offsetTop <= scrollY) current = section;
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
