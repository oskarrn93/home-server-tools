const items = $input.all();
const thresholdGb = Number($env.DISK_FREE_THRESHOLD_GB) || 50;
const thresholdBytes = thresholdGb * 1024 ** 3;

// Multiple root folders can share one physical volume (e.g. /tv and
// /movies both live on hdd1) - de-dupe by free/total byte counts so the
// alert doesn't repeat the same volume under every root folder label.
const seen = new Map();
for (const { json } of items) {
  const key = `${json.freeBytes}:${json.totalBytes}`;
  if (!seen.has(key)) seen.set(key, json);
}

const low = [...seen.values()].filter((v) => v.freeBytes < thresholdBytes);
const toGb = (b) => (b / 1024 ** 3).toFixed(1);

return [{
  json: {
    lowCount: low.length,
    message: low
      .map((v) => `${v.label}: ${toGb(v.freeBytes)} GB free (threshold ${thresholdGb} GB)`)
      .join('\n'),
  },
  pairedItem: { item: 0 },
}];
