import assert from 'node:assert/strict';
import test from 'node:test';
import {parseFragment} from 'parse5';
import {renderWebScanner} from '../src/scanner-template.mjs';

const visit = (node, fn) => { fn(node); for (const child of node.childNodes ?? []) visit(child, fn); };
const attr = (node, name) => node.attrs?.find(item => item.name === name)?.value;
const find = (root, predicate) => { let result; visit(root, node => { if (!result && predicate(node)) result = node; }); return result; };
const text = node => node.nodeName === '#text' ? node.value : (node.childNodes ?? []).map(text).join('');

test('generic TCG lookup stays on the identifier page and requires a published game choice', () => {
 const html = renderWebScanner({mode:'tcg', query:'BT1-001', tcgGames:[{slug:'game-71', name:'Digimon'}, {slug:'lorcana', name:'Disney Lorcana'}], selectedGame:'game-71'});
 const root = parseFragment(html);
 const scanner = find(root, node => attr(node, 'data-web-scanner') !== undefined);
 const form = find(root, node => node.tagName === 'form' && attr(node, 'method') === 'get');
 const select = find(form, node => node.tagName === 'select');
 assert.equal(attr(scanner, 'data-mode'), 'tcg');
 assert.equal(attr(form, 'action'), '/card-identifier');
 assert.equal(attr(select, 'name'), 'game');
 assert.equal(attr(select, 'required'), '');
 assert.equal(attr(select, 'id'), 'web-scanner-game');
 assert.equal(text(find(root, node => node.tagName === 'label' && attr(node, 'for') === 'web-scanner-game')), 'Game');
 assert.equal(attr(find(select, node => node.tagName === 'option' && attr(node, 'selected') !== undefined), 'value'), 'game-71');
 assert.equal(attr(find(form, node => node.tagName === 'input' && attr(node, 'name') === 'q'), 'value'), 'BT1-001');
 assert.match(html, /Choose a game/);
 assert.doesNotMatch(html, /Choose a sport|all TCGs/i);
});

test('the TCG option does not alter the Pokémon or sports lookup owners or leak escaped query markup', () => {
 const pokemon = parseFragment(renderWebScanner({mode:'pokemon'}));
 assert.equal(attr(find(pokemon, node => node.tagName === 'form' && attr(node, 'method') === 'get'), 'action'), '/pokemon-card-scanner');
 assert.equal(find(pokemon, node => node.tagName === 'select'), undefined);
 const sports = parseFragment(renderWebScanner({mode:'sports', sportsGames:[{slug:'basketball', name:'Basketball'}]}));
 assert.equal(attr(find(sports, node => node.tagName === 'form' && attr(node, 'method') === 'get'), 'action'), '/sports-card-scanner');
 assert.equal(attr(find(sports, node => node.tagName === 'select'), 'id'), 'web-scanner-sport');
 const query = '\"><img src=x onerror=alert(1)>';
 const tcg = parseFragment(renderWebScanner({mode:'tcg', query}));
 assert.equal(attr(find(tcg, node => node.tagName === 'input' && attr(node, 'name') === 'q'), 'value'), query);
 assert.equal(find(tcg, node => node.tagName === 'img' && attr(node, 'onerror') !== undefined), undefined);
});
