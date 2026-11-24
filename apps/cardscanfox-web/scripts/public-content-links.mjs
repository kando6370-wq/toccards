import {isPublicLinkAllowed} from '../src/public-links.mjs';

// Preserve the visible source text and its formatting when unwrapping a link.
export function retainPublicLinks(parent) {
  if (!parent.childNodes) return;
  parent.childNodes = parent.childNodes.flatMap(node => {
    retainPublicLinks(node);
    if (node.tagName !== 'a') return [node];
    const href = node.attrs.find(attr => attr.name === 'href');
    if (!href || isPublicLinkAllowed(href.value)) return [node];
    for (const child of node.childNodes) child.parentNode = parent;
    return node.childNodes;
  });
}
