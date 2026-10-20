// Rules for `mdat expand readme.md`. MDAT is installed globally rather than as a
// project dependency, so this file cannot import from it at runtime.

const wiki = "https://raw.githubusercontent.com/wiki/davedelong/DDMathParser";
const operatorsSource = `${wiki}/Basic/Operators.md`;
const functionsSource = `${wiki}/Basic/Functions.md`;

/** The HTML entities used by the DDMathParser wiki's operators table. */
const namedEntities: Record<string, string> = {
  and: "∧",
  divide: "÷",
  gt: ">",
  lt: "<",
  minus: "−",
  nbsp: " ",
  not: "¬",
  or: "∨",
  times: "×",
};

function decodeEntities(html: string): string {
  return html.replaceAll(/&(#?\w+);/gu, (reference, name: string) => {
    const character = namedEntities[name];
    if (character === undefined) {
      throw new Error(
        `Unknown HTML entity ${reference} in ${operatorsSource}. Add it to namedEntities in mdat.config.ts.`,
      );
    }
    return character;
  });
}

/** Converts a table cell's HTML, which contains only text and `<code>` spans. */
function markdownCell(html: string): string {
  const markdown = html
    .split(/(<code>.*?<\/code>)/u)
    .map((part) => {
      const code = /^<code>(.*)<\/code>$/u.exec(part)?.[1];
      return code === undefined
        ? decodeEntities(part)
        : `\`${decodeEntities(code)}\``;
    })
    .join("");
  // GitHub tables need pipes escaped, even inside code spans.
  return markdown.replaceAll("|", String.raw`\|`).trim();
}

function tableRow(cells: string[]): string {
  return `| ${cells.join(" | ")} |`;
}

async function fetchWikiPage(url: string): Promise<string> {
  let response: Response;
  try {
    response = await fetch(url);
  } catch (error) {
    throw new Error(
      `Fetching ${url} failed. Embedding wiki content needs network access.`,
      { cause: error },
    );
  }
  if (!response.ok) {
    throw new Error(
      `Fetching ${url} failed with HTTP ${response.status}. Check the URL and your network connection.`,
    );
  }
  return response.text();
}

/**
 * Converts the first HTML table in `page` to Markdown. Rows that span every column
 * name a category of operators, and are left out.
 */
function markdownTable(page: string): string {
  const table = /<table>([\s\S]*?)<\/table>/u.exec(page)?.[1];
  if (table === undefined) {
    throw new Error(
      `No <table> found in ${operatorsSource}. The wiki page may have changed.`,
    );
  }

  const rows = [...table.matchAll(/<tr>([\s\S]*?)<\/tr>/gu)].map(
    ([, row = ""]) =>
      [...row.matchAll(/<t[hd]([^>]*)>([\s\S]*?)<\/t[hd]>/gu)].map(
        ([, attributes = "", content = ""]) => ({
          content: markdownCell(content),
          spansColumns: attributes.includes("colspan"),
        }),
      ),
  );
  const [header, ...body] = rows;
  if (header === undefined || body.length === 0) {
    throw new Error(
      `The table in ${operatorsSource} has no rows. The wiki page may have changed.`,
    );
  }

  const columns = header.length;
  const operatorRows = body.filter(
    (cells) => !(cells.length === 1 && cells[0]?.spansColumns),
  );
  for (const cells of operatorRows) {
    if (cells.length !== columns) {
      throw new Error(
        `A row in ${operatorsSource} has ${cells.length} cells instead of ${columns}. The wiki page may have changed.`,
      );
    }
  }
  return [
    tableRow(header.map((cell) => cell.content)),
    tableRow(header.map(() => "---")),
    ...operatorRows.map((cells) => tableRow(cells.map((cell) => cell.content))),
  ].join("\n");
}

/**
 * The wiki lists "Π", the Greek capital pi, as an alias for `product`. DDMathParser
 * registers "∏", the n-ary product sign, instead. "Π" lowercases to the constant "π".
 */
const functionCorrections: Record<string, string> = { Π: "∏" };

/**
 * Returns the function names in `page`, in order and without duplicates, from code
 * spans that hold only a name, such as `sin()` or `asin`. Examples with arguments,
 * such as `nthroot(27,3)`, are left out.
 */
function functionNames(page: string): string[] {
  const names = [...page.matchAll(/`([^`]+)`/gu)]
    .map(
      ([, code = ""]) =>
        /^(?<name>[^\s()",]+)(?:\(\))?$/u.exec(code)?.groups?.["name"],
    )
    .filter((name) => name !== undefined)
    .map((name) => functionCorrections[name] ?? name);
  if (names.length === 0) {
    throw new Error(
      `No function names found in ${functionsSource}. The wiki page may have changed.`,
    );
  }
  return [...new Set(names)];
}

/** Embeds the DDMathParser wiki's operators table as Markdown: `<!-- operators -->`. */
async function operators(): Promise<string> {
  return markdownTable(await fetchWikiPage(operatorsSource));
}

/** Embeds the DDMathParser wiki's function names as one list: `<!-- functions -->`. */
async function functions(): Promise<string> {
  const names = functionNames(await fetchWikiPage(functionsSource));
  return names.map((name) => `\`${name}\``).join(", ");
}

const config = { functions, operators };

export default config;
