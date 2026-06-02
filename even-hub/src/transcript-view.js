const DEFAULT_TRANSCRIPT_COLUMNS = 38;
const DEFAULT_TRANSCRIPT_VISIBLE_LINES = 9;
const DEFAULT_TRANSCRIPT_REVIEW_LINES = 40;
const POPUP_TRANSCRIPT_COLUMNS = 36;
const POPUP_TRANSCRIPT_VISIBLE_LINES = 6;
const POPUP_TRANSCRIPT_REVIEW_LINES = 24;

export function wrapTranscriptLine(line, width = DEFAULT_TRANSCRIPT_COLUMNS) {
  const text = String(line || '').trim();
  if (!text) {
    return [''];
  }

  const words = text.split(/\s+/);
  const rows = [];
  let current = '';

  for (const word of words) {
    if (!current) {
      if (word.length <= width) {
        current = word;
        continue;
      }

      rows.push(...splitLongWord(word, width));
      current = '';
      continue;
    }

    const candidate = `${current} ${word}`;
    if (candidate.length <= width) {
      current = candidate;
      continue;
    }

    rows.push(current);
    if (word.length <= width) {
      current = word;
      continue;
    }

    rows.push(...splitLongWord(word, width));
    current = '';
  }

  if (current) {
    rows.push(current);
  }

  return rows.length ? rows : [''];
}

export function buildTranscriptRenderLines(sourceLines, options = {}) {
  const popup = options.popup === true;
  const follow = options.follow !== false;
  const width = popup ? POPUP_TRANSCRIPT_COLUMNS : DEFAULT_TRANSCRIPT_COLUMNS;
  const visibleLines = popup ? POPUP_TRANSCRIPT_VISIBLE_LINES : DEFAULT_TRANSCRIPT_VISIBLE_LINES;
  const reviewLines = popup ? POPUP_TRANSCRIPT_REVIEW_LINES : DEFAULT_TRANSCRIPT_REVIEW_LINES;

  const wrapped = (Array.isArray(sourceLines) ? sourceLines : [''])
    .flatMap((line) => wrapTranscriptLine(line, width))
    .filter((line) => line !== '');

  if (!wrapped.length) {
    return ['Waiting for the first Codex transcript.'];
  }

  return follow ? wrapped.slice(-visibleLines) : wrapped.slice(-reviewLines);
}

function splitLongWord(word, width) {
  const parts = [];
  for (let offset = 0; offset < word.length; offset += width) {
    parts.push(word.slice(offset, offset + width));
  }
  return parts;
}
