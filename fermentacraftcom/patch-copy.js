// FermentaCraft runtime patch v10: image rewrite w/ allowlist + store-badge skip
(function(){
  console.log('[patch] v10 starting');

  function onReady(fn){
    if (document.readyState === 'complete' || document.readyState === 'interactive') setTimeout(fn,0);
    else { addEventListener('DOMContentLoaded', fn); addEventListener('load', fn); }
  }

  // ------- TEXT (unchanged from your v9) -------
  function replaceText(fromArr, to){
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
    const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
    let hits = 0;
    nodes.forEach(n=>{
      let v = n.nodeValue; if(!v) return;
      let changed=false;
      fromArr.forEach(f=>{ if(v.indexOf(f)!==-1){ v=v.split(f).join(to); changed=true; }});
      if(changed){ n.nodeValue=v; hits++; }
    });
    if (hits) console.log(`[patch] text -> "${to}" (${hits})`);
    return hits;
  }

  const REPL = [
    {from:['Cider & Mead Recipe Builder'], to:'Plan. Brew. Perfect.'},
    {from:['Build Better Recipes'], to:'Build better recipes'},
    {from:['Track Fermentation'], to:'Track fermentation like a pro'},
    {from:['Tools You’ll Actually Use','Tools You\'ll Actually Use','Tools Youâ€™ll Actually Use'], to:'Tools that earn their keep'},
    {from:['Keep Tabs on Ingredients'], to:'Keep tabs on ingredients'},
    {from:['Preferences, Sync & Reliability'], to:'Preferences that fit your workflow'},
    {from:['SO₂','SO2','SOâ‚‚'], to:'SO2'},
    {from:['sorbate','Sorbate'], to:'sorbate'}
  ];

  // ------- IMAGE REMAP -------
  const OWN_HOST = location.host;

  // Allow-list specific external assets we *never* want to rewrite (your MS Store badges)
  const ALLOWLIST_URLS = new Set([
    'https://static.wikia.nocookie.net/logopedia/images/d/df/Microsoft_Store_2021_Light.svg',
    'https://static.wikia.nocookie.net/logopedia/images/b/bf/Microsoft_Store_2021_Dark.svg'
  ]);

  const TARGETS = [
    '/screenshots/01.png','/screenshots/02.png','/screenshots/03.png','/screenshots/04.png','/screenshots/05.png',
    '/screenshots/06.png','/screenshots/07.png','/screenshots/08.png','/screenshots/09.png','/screenshots/10.png'
  ];
  function makeSequencer(){ let i=0; return ()=> TARGETS[Math.min(i++, TARGETS.length-1)]; }
  const nextShot = makeSequencer();

  function isAllowlisted(u){
    if (!u) return false;
    try {
      const abs = new URL(u, location.origin).href;
      return ALLOWLIST_URLS.has(abs);
    } catch { return false; }
  }

  function isExternalUrl(u){
    if (!u) return false;
    if (u.startsWith('data:')) return false;
    if (isAllowlisted(u)) return false;            // <— NEW: respect allowlist
    try {
      const url = new URL(u, location.origin);
      return url.host !== OWN_HOST;
    } catch { return false; }
  }

  // Treat site logo + app store badges as protected brand art
  function isBrandArt(el){
    if (!el || !el.getAttribute) return false;

    // explicit opt-out via attribute (you can add data-preserve on any parent)
    if (el.closest && el.closest('[data-preserve]')) return true;

    const alt = (el.getAttribute('alt')||'').toLowerCase();
    const cls = (el.getAttribute('class')||'').toLowerCase();
    const href = (el.closest && el.closest('a') && el.closest('a').getAttribute('href')) || '';

    // your original logo rules
    if (alt.includes('logo') || alt.includes('fermentacraft')) return true;
    if (cls.includes('logo')) return true;
    if (el.closest && (el.closest('header') || el.closest('nav'))) return true;

    // NEW: treat common store badges as brand art
    const brandHints = alt + ' ' + cls;
    if (/(microsoft store|windows|google play|app store|store badge|badge)/i.test(brandHints)) return true;
    if (/(apps\.microsoft\.com|play\.google\.com|apple\.com\/app-store)/i.test(href||'')) return true;

    // If the element itself is the <picture>, check its <img alt>
    if (el.tagName && el.tagName.toLowerCase() === 'picture') {
      const picImg = el.querySelector('img');
      if (picImg) return isBrandArt(picImg);
    }
    return false;
  }

  function remapImgs(){
    let imgChanged=0, srcsetChanged=0, dataChanged=0;

    // 1) <img src>
    document.querySelectorAll('img').forEach(img=>{
      if (isBrandArt(img)) return; // <— protect
      const srcAttr = img.getAttribute('src');
      const srcAbs  = srcAttr || img.src || '';
      if (isExternalUrl(srcAbs)) {
        const to = nextShot();
        img.setAttribute('src', to);
        img.removeAttribute('srcset'); img.removeAttribute('sizes');
        imgChanged++;
      }
    });

    // 2) <img srcset>
    document.querySelectorAll('img[srcset]').forEach(img=>{
      if (isBrandArt(img)) return; // <— protect
      const ss = img.getAttribute('srcset') || '';
      if (isExternalUrl(ss)) {
        const to = nextShot();
        img.setAttribute('srcset', `${to} 1x`);
        img.removeAttribute('sizes');
        srcsetChanged++;
      }
    });

    // 3) data-src / data-srcset
    document.querySelectorAll('img[data-src], img[data-srcset]').forEach(img=>{
      if (isBrandArt(img)) return; // <— protect
      const ds  = img.getAttribute('data-src');
      const dss = img.getAttribute('data-srcset');
      if (isExternalUrl(ds)) {
        const to = nextShot();
        img.setAttribute('src', to);
        img.removeAttribute('data-src');
        dataChanged++;
      }
      if (isExternalUrl(dss)) {
        const to2 = nextShot();
        img.setAttribute('srcset', `${to2} 1x`);
        img.removeAttribute('data-srcset');
        dataChanged++;
      }
    });

    if (imgChanged || srcsetChanged || dataChanged) {
      console.log(`[patch] img rewrites src:${imgChanged} srcset:${srcsetChanged} data:*:${dataChanged}`);
    }
    return imgChanged + srcsetChanged + dataChanged;
  }

  function remapSources(){
    // <picture><source srcset|data-srcset>
    let sourceChanged=0;
    document.querySelectorAll('picture source').forEach(source=>{
      // If the <picture> or its <img> is brand art, skip the source rewrite
      const pic = source.parentElement;
      if (pic && (isBrandArt(pic) || (pic.querySelector && isBrandArt(pic.querySelector('img'))))) return;

      const ss = source.getAttribute('srcset');
      const dss = source.getAttribute('data-srcset');

      if (isExternalUrl(ss)) {
        const to = nextShot(); source.setAttribute('srcset', `${to} 1x`); sourceChanged++;
      }
      if (isExternalUrl(dss)) {
        const to2 = nextShot(); source.setAttribute('srcset', `${to2} 1x`); source.removeAttribute('data-srcset'); sourceChanged++;
      }
    });
    if (sourceChanged) console.log(`[patch] <source> rewrites: ${sourceChanged}`);
    return sourceChanged;
  }

  function remapComputedBackgrounds(){
    // Scan all elements; if computed background-image points to an external url, inline replace
    let bgChanged=0;
    const els = document.querySelectorAll('*');
    els.forEach(el=>{
      if (isBrandArt(el)) return; // <— protect
      const bg = getComputedStyle(el).backgroundImage;
      if (!bg || bg === 'none') return;
      const m = bg.match(/url\((["']?)(.*?)\1\)/);
      if (!m) return;
      const url = m[2];
      if (isExternalUrl(url)) {
        const to = nextShot();
        el.style.backgroundImage = `url(${to})`;
        bgChanged++;
      }
    });
    if (bgChanged) console.log(`[patch] background-image rewrites: ${bgChanged}`);
    return bgChanged;
  }

  function updateMeta(property, content){
    const el = document.querySelector(`meta[property="${property}"]`) || document.querySelector(`meta[name="${property}"]`);
    if (el && el.getAttribute('content') !== content) { el.setAttribute('content', content); console.log('[patch] meta '+property+' -> '+content); return 1; }
    return 0;
  }

  function applyAll(){
    let textTotal = 0; REPL.forEach(r=> textTotal += replaceText(r.from, r.to));
    const i1 = remapImgs();
    const i2 = remapSources();
    const i3 = remapComputedBackgrounds();
    const metaCount = updateMeta('og:image', 'https://fermentacraft.com/screenshots/cover1.png');
    console.log(`[patch] summary text:${textTotal} remaps:${i1+i2+i3} (imgs:${i1} sources:${i2} bg:${i3}) meta:${metaCount}`);
  }

  function waitForMount(cb){
    const start = Date.now(), maxMs = 20000;
    const timer = setInterval(function(){
      if (document.querySelector('#root *')){ clearInterval(timer); cb(); }
      if (Date.now()-start>maxMs){ clearInterval(timer); cb(); }
    }, 200);
  }

  function observeMutations(){
    const root = document.querySelector('#root'); if (!root) return;
    let t=null; const mo = new MutationObserver(function(){ clearTimeout(t); t=setTimeout(applyAll, 250); });
    mo.observe(root, { childList:true, subtree:true });
  }

  onReady(function(){ waitForMount(function(){ applyAll(); observeMutations(); console.log('[patch] v10 applied'); }); });
})();
