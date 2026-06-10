import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');
const queuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-strict-artist-preview-queue.json',
);

function readQueue() {
  return JSON.parse(fs.readFileSync(queuePath, 'utf8').replace(/^\uFEFF/, ''));
}

function artistTokenCount(prompt, token) {
  const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return (prompt.match(new RegExp(escaped, 'g')) || []).length;
}

test('strict artist preview queue pins generation parameters explicitly', () => {
  const queue = readQueue().filter((item) => item.type === 'artist_chain_preview');

  assert.ok(queue.length > 0, 'expected artist preview queue items');

  for (const item of queue) {
    assert.equal(item.model, 'nai-diffusion-4-5-full', item.id);
    assert.equal(item.action, 'generate', item.id);
    assert.equal(item.steps, 28, item.id);
    assert.equal(item.sampler, 'k_euler_ancestral', item.id);
    assert.equal(item.noise_schedule, 'karras', item.id);
    assert.equal(item.scale, 6.6, item.id);
    assert.equal(item.cfg_rescale, 0.1, item.id);
    assert.equal(item.ucPreset, 2, item.id);
    assert.equal(item.qualityToggle, false, item.id);
    assert.equal(item.dynamic_thresholding, false, item.id);
    assert.equal(item.legacy, false, item.id);
    assert.equal(item.legacy_uc, false, item.id);
    assert.equal(item.use_coords, true, item.id);
    assert.equal(item.use_order, true, item.id);
    assert.match(item.negativePrompt, /oversaturated|overexposed/, item.id);

    if (item.mode === 'background') {
      assert.equal(item.width, 1216, item.id);
      assert.equal(item.height, 832, item.id);
    } else {
      assert.equal(item.width, 1024, item.id);
      assert.equal(item.height, 1024, item.id);
    }
  }
});

test('strict artist preview queue does not duplicate structured artist tokens', () => {
  const queue = readQueue();
  const chenpeipeiii = queue.find(
    (item) =>
      item.artistChainId === 'legacy-artist-sheet-r6c1' &&
      item.type === 'artist_chain_preview',
  );
  const controlline3 = queue.find(
    (item) =>
      item.artistChainId === 'legacy-artist-sheet-r10c7' &&
      item.type === 'artist_chain_preview',
  );

  assert.ok(chenpeipeiii, 'expected chenpeipeiii strict preview item');
  assert.ok(controlline3, 'expected controlline3 strict preview item');

  assert.equal(artistTokenCount(chenpeipeiii.prompt, 'artist:chenpeipeiii'), 1);
  assert.equal(artistTokenCount(controlline3.prompt, 'artist:controlline3'), 1);
  assert.doesNotMatch(chenpeipeiii.prompt, /,\s+::artist:/);
});

test('strict artist preview queue keeps raw artist-chain phrasing for style fidelity', () => {
  const queue = readQueue();
  const dishwasher1910 = queue.find(
    (item) =>
      item.artistChainId === 'legacy-artist-sheet-r4c1' &&
      item.type === 'artist_chain_preview',
  );

  assert.ok(dishwasher1910, 'expected dishwasher1910 strict preview item');
  assert.match(dishwasher1910.prompt, /artist: kim hyung tae ::/);
  assert.match(dishwasher1910.prompt, /2::3d, photorealistic::/);
  assert.match(dishwasher1910.prompt, /\bgirl\b/);
  assert.match(dishwasher1910.prompt, /safe, non-explicit, tasteful outfit/);
});
