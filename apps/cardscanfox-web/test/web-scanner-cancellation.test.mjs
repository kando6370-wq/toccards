import assert from 'node:assert/strict';
import test from 'node:test';
import {waitForScan} from '../public/assets/web-scanner.js';

function deferred() {
 let resolve, reject;
 const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
 return {promise, resolve, reject};
}

test('clearing a scan releases a pending model wait while the next scan can reuse the same load', async () => {
 const model = deferred(), cleared = new AbortController(), next = new AbortController();
 const firstWait = waitForScan(model.promise, cleared.signal);
 const firstRejected = assert.rejects(firstWait, {name: 'AbortError'});
 cleared.abort();
 await firstRejected;
 const nextWait = waitForScan(model.promise, next.signal);
 const session = {name: 'shared-model'};
 model.resolve(session);
 assert.equal(await nextWait, session);
});

test('a scan timeout releases a pending inference wait and does not replace its reason', async () => {
 const inference = deferred(), controller = new AbortController();
 const timeout = new Error('This scan took too long.');
 const waiting = waitForScan(inference.promise, controller.signal);
 const rejected = assert.rejects(waiting, error => error === timeout);
 controller.abort(timeout);
 await rejected;
 // The underlying model may finish later; its result cannot settle the cancelled wait.
 inference.resolve([1, 0, 0]);
});

test('a late failure from a cancelled shared load is handled without reviving the old wait', async () => {
 const model = deferred(), controller = new AbortController();
 controller.abort();
 await assert.rejects(waitForScan(model.promise, controller.signal), {name: 'AbortError'});
 model.reject(new Error('Model download failed after cancellation.'));
 await Promise.resolve();
});

test('an active wait preserves successful inference and model errors', async () => {
 const controller = new AbortController(), vector = [1, 2, 3];
 assert.equal(await waitForScan(Promise.resolve(vector), controller.signal), vector);
 const failure = new Error('Model unavailable.');
 await assert.rejects(waitForScan(Promise.reject(failure), controller.signal), error => error === failure);
});
