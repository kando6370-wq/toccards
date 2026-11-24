// Approved intent consolidations keep one functional owner per task.
const targets = Object.freeze({
 '/blog/pokemon-card-values': '/games/pokemon',
 '/digimon-card-scanner': '/card-identifier#digimon',
 '/lorcana-card-scanner': '/card-identifier#lorcana',
 '/dragon-ball-super-card-scanner': '/card-identifier#dragon-ball-super',
 '/flesh-and-blood-card-scanner': '/card-identifier#flesh-and-blood',
 '/about/': '/about',
 '/ai-card-recognition-accuracy': '/ai-card-recognition-accuracy/',
 '/card-price-data-methodology': '/card-price-data-methodology/',
 '/compare': '/compare/',
});
export function redirectTarget(path) {
 const canonical = path.endsWith('.html') ? path.slice(0, -5) : path;
 return targets[canonical] ?? null;
}
export function redirectLocation(path, search = '') {
 const target = redirectTarget(path);
 if (!target) return null;
 const location = new URL(target, 'https://tcgcard.fun');
 location.search = search;
 return location.pathname + location.search + location.hash;
}
