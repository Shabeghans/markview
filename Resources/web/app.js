(function () {
  'use strict';
  var content = document.getElementById('content');
  var toc = document.getElementById('toc');
  var mermaidSrc = document.body.getAttribute('data-mermaid-src');
  var mermaidLoading = null;

  function post(name, body) {
    var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name];
    if (h) h.postMessage(body);
  }

  // GitHub-style heading anchors.
  function slugify(text, seen) {
    var base = text.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, '')
      .replace(/\s/g, '-') || 'section';
    var slug = base, n = 1;
    while (seen[slug]) slug = base + '-' + n++;
    seen[slug] = true;
    return slug;
  }

  function buildTOC() {
    var seen = {};
    var headings = content.querySelectorAll('h1, h2, h3, h4');
    var frag = document.createDocumentFragment();
    headings.forEach(function (h) {
      if (!h.id) h.id = slugify(h.textContent, seen); else seen[h.id] = true;
      var a = document.createElement('a');
      a.href = '#' + h.id;
      a.textContent = h.textContent;
      a.className = 'l' + h.tagName.charAt(1);
      a.title = h.textContent;
      frag.appendChild(a);
    });
    toc.replaceChildren(frag);
    if (!headings.length) {
      var empty = document.createElement('p');
      empty.className = 'toc-empty';
      empty.textContent = 'No headings';
      toc.appendChild(empty);
    }
  }

  function addCopyButton(pre, getText) {
    var wrap = document.createElement('div');
    wrap.className = 'code-wrap';
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    var btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.type = 'button';
    btn.textContent = 'Copy';
    btn.addEventListener('click', function () {
      post('copy', getText());
      btn.textContent = 'Copied';
      setTimeout(function () { btn.textContent = 'Copy'; }, 1200);
    });
    wrap.appendChild(btn);
  }

  function enhanceCode() {
    var mermaidNodes = [];
    content.querySelectorAll('pre > code').forEach(function (code) {
      var pre = code.parentNode;
      var lang = (code.className.match(/language-([\w+#.-]+)/) || [])[1];
      var source = code.textContent;
      if (lang === 'mermaid') {
        var div = document.createElement('div');
        div.className = 'mermaid';
        div.textContent = source;
        pre.replaceWith(div);
        mermaidNodes.push(div);
        return;
      }
      if (lang && window.hljs && hljs.getLanguage(lang)) {
        try { hljs.highlightElement(code); } catch (e) {}
      }
      addCopyButton(pre, function () { return source; });
    });
    if (mermaidNodes.length) renderMermaid(mermaidNodes);
  }

  function loadMermaid() {
    if (!mermaidLoading) {
      mermaidLoading = new Promise(function (resolve, reject) {
        var s = document.createElement('script');
        s.src = mermaidSrc;
        s.onload = function () { resolve(window.mermaid); };
        s.onerror = reject;
        document.head.appendChild(s);
      });
    }
    return mermaidLoading;
  }

  var pendingDiagrams = 0;   // Mermaid renders in flight; see MV.isReady

  function renderMermaid(nodes) {
    pendingDiagrams++;
    loadMermaid().then(function (mermaid) {
      var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
      return mermaid.run({ nodes: nodes, suppressErrors: true });
    }).catch(function () {}).then(function () { pendingDiagrams--; });
  }

  function imagesLoaded() {
    return Array.prototype.every.call(content.querySelectorAll('img'), function (img) { return img.complete; });
  }

  function enhance() {
    buildTOC();
    enhanceCode();
  }

  // ---- Find in page -------------------------------------------------------
  // Matches are found in the concatenated text of the document, so they can
  // span formatting (e.g. "bold text" across <strong>). Highlighting uses the
  // CSS Custom Highlight API, which leaves the DOM untouched.
  var finder = { query: '', ranges: [], index: -1 };
  var hasHighlights = !!(window.CSS && CSS.highlights && window.Highlight);

  function collectTextNodes() {
    var nodes = [], starts = [], text = '';
    var walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        return n.parentElement && n.parentElement.closest('.copy-btn, script, style')
          ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }
    });
    var node;
    while ((node = walker.nextNode())) {
      nodes.push(node);
      starts.push(text.length);
      text += node.nodeValue;
    }
    return { nodes: nodes, starts: starts, text: text };
  }

  // Maps an offset in the concatenated text to [node, offsetInNode].
  function locate(map, offset, isEnd) {
    var lo = 0, hi = map.nodes.length - 1;
    while (lo < hi) {
      var mid = (lo + hi + 1) >> 1;
      if (map.starts[mid] < offset || (!isEnd && map.starts[mid] === offset)) lo = mid; else hi = mid - 1;
    }
    return [map.nodes[lo], offset - map.starts[lo]];
  }

  function paintFind() {
    if (hasHighlights) {
      CSS.highlights.delete('mv-find');
      CSS.highlights.delete('mv-find-current');
      if (finder.ranges.length) {
        var all = new Highlight();
        finder.ranges.forEach(function (r) { all.add(r); });
        CSS.highlights.set('mv-find', all);
        if (finder.index >= 0) CSS.highlights.set('mv-find-current', new Highlight(finder.ranges[finder.index]));
      }
    } else if (finder.index >= 0) {
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(finder.ranges[finder.index]);
    }
  }

  function scrollToCurrent() {
    if (finder.index < 0) return;
    var rect = finder.ranges[finder.index].getBoundingClientRect();
    if (rect.top < 60 || rect.bottom > window.innerHeight - 40) {
      window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight / 3 });
    }
  }

  function findState() {
    return { count: finder.ranges.length, index: Math.max(finder.index, 0) };
  }

  // Recomputes matches. mode: 'fromViewport' (new search), 'keep' (after a re-render).
  function search(query, mode) {
    finder.query = query;
    finder.ranges = [];
    var previous = finder.index;
    finder.index = -1;
    if (query) {
      var map = collectTextNodes();
      var hay = map.text.toLowerCase(), needle = query.toLowerCase();
      var i = hay.indexOf(needle);
      while (i !== -1 && finder.ranges.length < 5000) {
        var start = locate(map, i, false), end = locate(map, i + needle.length, true);
        var r = document.createRange();
        r.setStart(start[0], start[1]);
        r.setEnd(end[0], end[1]);
        finder.ranges.push(r);
        i = hay.indexOf(needle, i + needle.length);
      }
    }
    if (finder.ranges.length) {
      if (mode === 'keep') {
        finder.index = Math.min(Math.max(previous, 0), finder.ranges.length - 1);
      } else {
        finder.index = 0;
        for (var k = 0; k < finder.ranges.length; k++) {
          if (finder.ranges[k].getBoundingClientRect().bottom > 0) { finder.index = k; break; }
        }
      }
    }
    paintFind();
    if (mode !== 'keep') scrollToCurrent();
    return findState();
  }

  window.MV = {
    render: function (html) {
      content.innerHTML = html;
      enhance();
      return finder.query ? search(finder.query, 'keep') : findState();
    },
    find: function (query) { return search(query, 'fromViewport'); },
    findStep: function (step) {
      var n = finder.ranges.length;
      if (!n) return findState();
      finder.index = (finder.index + step + n) % n;
      paintFind();
      scrollToCurrent();
      return findState();
    },
    findClear: function () {
      finder.query = '';
      finder.ranges = [];
      finder.index = -1;
      if (hasHighlights) { CSS.highlights.delete('mv-find'); CSS.highlights.delete('mv-find-current'); }
      return findState();
    },
    // True once the page, images and Mermaid diagrams are done (used before printing/PDF export).
    isReady: function () {
      return document.readyState === 'complete' && pendingDiagrams === 0 && imagesLoaded();
    },
    setTOC: function (show) {
      document.body.classList.toggle('toc-open', !!show);
    }
  };

  enhance();
})();
