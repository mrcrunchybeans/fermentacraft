'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"apple-icon-180.png": "db62647644d96a85d2ce9f4b2e940f55",
"apple-splash-1125-2436.jpg": "b910d13f99a90c35b49fd721b5af336a",
"apple-splash-1136-640.jpg": "063d455e1e5edbb6c3defb06228e55ff",
"apple-splash-1170-2532.jpg": "547786d11480072c2cff938009b585de",
"apple-splash-1179-2556.jpg": "0689ee566a815ba9703ae3a1dbbdc820",
"apple-splash-1206-2622.jpg": "3dc4a9aa672a7f27a6c079aafe176b20",
"apple-splash-1242-2208.jpg": "1163badefa28e3e5b4d016b5461f04b4",
"apple-splash-1242-2688.jpg": "ff94cd41ed71c1f4d92f29ee490fd2a5",
"apple-splash-1284-2778.jpg": "cb65b12ddaef084dcdd6ad7f0960efb4",
"apple-splash-1290-2796.jpg": "dd8c4097756ec1ced14eee86418c2685",
"apple-splash-1320-2868.jpg": "cb19a512001bb1ef5d77de85efaa4713",
"apple-splash-1334-750.jpg": "9412a10b17b2cfbd9f22d0c23cbebab9",
"apple-splash-1488-2266.jpg": "25ab9430ea23b514e8dd688c2fdbbca7",
"apple-splash-1536-2048.jpg": "803f383b87158a627676653d8a05a5af",
"apple-splash-1620-2160.jpg": "07fc694cf364e814e93673b1a95dc58e",
"apple-splash-1640-2360.jpg": "afcbabc03b9c93fe245fbe761b22d457",
"apple-splash-1668-2224.jpg": "90b059e68fcca65912761490a3095c5f",
"apple-splash-1668-2388.jpg": "97d060a3eea47d7a943cdd927c95b196",
"apple-splash-1792-828.jpg": "07816392e084a4384ad7967443f2f629",
"apple-splash-2048-1536.jpg": "3f99dca5a9a72360ef4e220eeebe3a94",
"apple-splash-2048-2732.jpg": "a82e98ade1ba77cf36387147b87d083e",
"apple-splash-2160-1620.jpg": "1b3efe3eae9e4bc9ee3099e9dd1d7f06",
"apple-splash-2208-1242.jpg": "c518d8a7a76f98bb3bc894fc55f87b29",
"apple-splash-2224-1668.jpg": "734ba412ea5f239f116df72e6a487ce5",
"apple-splash-2266-1488.jpg": "f5980432db3f3c64c26e5d33fb51186e",
"apple-splash-2360-1640.jpg": "276c2a77c3c59d51eb343d5df99a49d5",
"apple-splash-2388-1668.jpg": "2d85ce188d422bf76afa3af28a3f1f31",
"apple-splash-2436-1125.jpg": "495d1f854e069849551c8750e35cdbde",
"apple-splash-2532-1170.jpg": "c90d27d76dce5258b628fccbabfc4ae0",
"apple-splash-2556-1179.jpg": "d9d588becfb38d49b184ccc5f2b7184d",
"apple-splash-2622-1206.jpg": "0b805199c869a21a2035e3733c093052",
"apple-splash-2688-1242.jpg": "9109f082853c04532afb26e075b993d0",
"apple-splash-2732-2048.jpg": "d1b5884348be318126147103056d53e0",
"apple-splash-2778-1284.jpg": "918d454156765e793f1876b50c90f1c3",
"apple-splash-2796-1290.jpg": "e5bbc54b4f5edbbd8759d5723a9173bf",
"apple-splash-2868-1320.jpg": "1f3d2b2b3d1144217895c6b5646dce03",
"apple-splash-640-1136.jpg": "3094dbc1b32a22e7648250e931203469",
"apple-splash-750-1334.jpg": "c739823d7359a8c499aeb34145d8be22",
"apple-splash-828-1792.jpg": "db2b4b6338b11196497658c1aa0f066a",
"assets/AssetManifest.bin": "b17f337bfea0fecdb83cb11fc6eae8b0",
"assets/AssetManifest.bin.json": "d68e0c8904f4d556e11e5ecc0d5081c2",
"assets/AssetManifest.json": "bdfaf734e4353ead6795c2f1c32e13b1",
"assets/assets/images/carboy.svg": "d994b42f83839a753df2a9258a6a27eb",
"assets/assets/images/fermentacraftlogo.png": "5aa84ea0de59f84a90fd63e451cfc0b1",
"assets/assets/images/fermentacraftlogo_darkmode.png": "8ef8aedf16bdfd8935bb2dbe7c3d48f5",
"assets/assets/images/fermentacraft_logo_carboy.png": "b138448b40d451565408c167f520b164",
"assets/assets/images/fermentacraft_logo_txt_darkmode%2520.png": "bf688e5abd4daa2894c3838761f6c87e",
"assets/assets/images/fermentacraft_logo_txt_darkmode.svg": "19b02cd410a0b46011658fadd0eaca43",
"assets/assets/images/fermentacraft_logo_txt_lightmode.png": "f485f8961693ed3913884d726e9c43f1",
"assets/assets/images/fermentacraft_logo_txt_lightmode.svg": "16f9be758dc4fa1b92ad171915e4dfc1",
"assets/assets/images/fermentacraft_txt_darkmode.png": "563553b67ebb81acddd05db5a129c86f",
"assets/assets/images/google.svg": "648fa9faea73bcefeebcdd3c28c94c38",
"assets/assets/images/icon.png": "913b23bc5458c5970fc2c78bf3a740bb",
"assets/assets/images/logo-150.png": "acf8e7ebd76e5fbbe5917fc17d437a3c",
"assets/assets/images/logo-300.png": "5f7d66db0283ed966fa7bdb938b5608f",
"assets/assets/images/logo-71.png": "ba530f85cd36dc9d1b8d9387ba77ebfc",
"assets/assets/images/logo.png": "b138448b40d451565408c167f520b164",
"assets/assets/images/logo256.png": "f6c80f554443a175f050f54e1f9e3094",
"assets/assets/images/phstrip_help.png": "16012af99b30d2c1bd20f5e0e76278f2",
"assets/assets/images/site.webmanifest": "053100cb84a50d2ae7f5492f7dd7f25e",
"assets/assets/phstrip_help.png": "855548a0cf9053b4425af2a99a283cdd",
"assets/FontManifest.json": "f713980e58bc3401a3bda70a18778fea",
"assets/fonts/LibreBaskerville-Bold.ttf": "0fd0abfccb6dd3a135d56af302a625b4",
"assets/fonts/LibreBaskerville-Italic.ttf": "6cc84cb9622c246920292e2ed2b64fa2",
"assets/fonts/LibreBaskerville-Regular.ttf": "b9fedaa06d0594ea4119b9f50502f140",
"assets/fonts/MaterialIcons-Regular.otf": "b5cac4d546e767e1a84bd3b78f6b8e93",
"assets/fonts/Roboto-Bold.ttf": "8c9110ec6a1737b15a5611dc810b0f92",
"assets/fonts/Roboto-Italic.ttf": "1fc3ee9d387437d060344e57a179e3dc",
"assets/fonts/Roboto-Light.ttf": "25e374a16a818685911e36bee59a6ee4",
"assets/fonts/Roboto-Regular.ttf": "303c6d9e16168364d3bc5b7f766cfff4",
"assets/NOTICES": "827ec034da400ee0149d0c13aa09a7cb",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"brand/carboy.svg": "d994b42f83839a753df2a9258a6a27eb",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon-196.png": "b1932d280f0b4a0605270a0b8f3e219b",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "dfe4ea7b08f3b48b93eee0e72e383876",
"icons/apple-icon-180.png": "db62647644d96a85d2ce9f4b2e940f55",
"icons/apple-splash-1125-2436.jpg": "b910d13f99a90c35b49fd721b5af336a",
"icons/apple-splash-1136-640.jpg": "063d455e1e5edbb6c3defb06228e55ff",
"icons/apple-splash-1170-2532.jpg": "547786d11480072c2cff938009b585de",
"icons/apple-splash-1179-2556.jpg": "0689ee566a815ba9703ae3a1dbbdc820",
"icons/apple-splash-1206-2622.jpg": "3dc4a9aa672a7f27a6c079aafe176b20",
"icons/apple-splash-1242-2208.jpg": "1163badefa28e3e5b4d016b5461f04b4",
"icons/apple-splash-1242-2688.jpg": "ff94cd41ed71c1f4d92f29ee490fd2a5",
"icons/apple-splash-1284-2778.jpg": "cb65b12ddaef084dcdd6ad7f0960efb4",
"icons/apple-splash-1290-2796.jpg": "dd8c4097756ec1ced14eee86418c2685",
"icons/apple-splash-1320-2868.jpg": "cb19a512001bb1ef5d77de85efaa4713",
"icons/apple-splash-1334-750.jpg": "9412a10b17b2cfbd9f22d0c23cbebab9",
"icons/apple-splash-1488-2266.jpg": "25ab9430ea23b514e8dd688c2fdbbca7",
"icons/apple-splash-1536-2048.jpg": "803f383b87158a627676653d8a05a5af",
"icons/apple-splash-1620-2160.jpg": "07fc694cf364e814e93673b1a95dc58e",
"icons/apple-splash-1640-2360.jpg": "afcbabc03b9c93fe245fbe761b22d457",
"icons/apple-splash-1668-2224.jpg": "90b059e68fcca65912761490a3095c5f",
"icons/apple-splash-1668-2388.jpg": "97d060a3eea47d7a943cdd927c95b196",
"icons/apple-splash-1792-828.jpg": "07816392e084a4384ad7967443f2f629",
"icons/apple-splash-2048-1536.jpg": "3f99dca5a9a72360ef4e220eeebe3a94",
"icons/apple-splash-2048-2732.jpg": "a82e98ade1ba77cf36387147b87d083e",
"icons/apple-splash-2160-1620.jpg": "1b3efe3eae9e4bc9ee3099e9dd1d7f06",
"icons/apple-splash-2208-1242.jpg": "c518d8a7a76f98bb3bc894fc55f87b29",
"icons/apple-splash-2224-1668.jpg": "734ba412ea5f239f116df72e6a487ce5",
"icons/apple-splash-2266-1488.jpg": "f5980432db3f3c64c26e5d33fb51186e",
"icons/apple-splash-2360-1640.jpg": "276c2a77c3c59d51eb343d5df99a49d5",
"icons/apple-splash-2388-1668.jpg": "2d85ce188d422bf76afa3af28a3f1f31",
"icons/apple-splash-2436-1125.jpg": "495d1f854e069849551c8750e35cdbde",
"icons/apple-splash-2532-1170.jpg": "c90d27d76dce5258b628fccbabfc4ae0",
"icons/apple-splash-2556-1179.jpg": "d9d588becfb38d49b184ccc5f2b7184d",
"icons/apple-splash-2622-1206.jpg": "0b805199c869a21a2035e3733c093052",
"icons/apple-splash-2688-1242.jpg": "9109f082853c04532afb26e075b993d0",
"icons/apple-splash-2732-2048.jpg": "d1b5884348be318126147103056d53e0",
"icons/apple-splash-2778-1284.jpg": "918d454156765e793f1876b50c90f1c3",
"icons/apple-splash-2796-1290.jpg": "e5bbc54b4f5edbbd8759d5723a9173bf",
"icons/apple-splash-2868-1320.jpg": "1f3d2b2b3d1144217895c6b5646dce03",
"icons/apple-splash-640-1136.jpg": "3094dbc1b32a22e7648250e931203469",
"icons/apple-splash-750-1334.jpg": "c739823d7359a8c499aeb34145d8be22",
"icons/apple-splash-828-1792.jpg": "db2b4b6338b11196497658c1aa0f066a",
"icons/favicon-196.png": "b1932d280f0b4a0605270a0b8f3e219b",
"icons/manifest-icon-192.maskable.png": "777f58f3a61632b024287da68fa63c6d",
"icons/manifest-icon-512.maskable.png": "4f2c8080346b7fafc69174de75951ad1",
"index.html": "ebd867dbad1854d7ea61805aaa1606b0",
"/": "ebd867dbad1854d7ea61805aaa1606b0",
"main.dart.js": "e7f0150c4eab5e52895bdd912b252ad7",
"manifest-icon-192.maskable.png": "777f58f3a61632b024287da68fa63c6d",
"manifest-icon-512.maskable.png": "4f2c8080346b7fafc69174de75951ad1",
"manifest.json": "8ce64094439e0b1b77727bb725bd080a",
"version.json": "a99e6452531508b63dc790e6f312ec86"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
