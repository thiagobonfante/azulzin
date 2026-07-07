# Data export — how it works

azulzin exports the account's movements as **XLSX** (the default), **CSV**, or a printable
**PDF "extrato"** — a trust/retention feature ("get my data out"). Every export is
account-scoped, posted + `.kept` only, fully localized (headers, dates, money), and
integer-cents-safe end to end. OFX is deferred (interop-only, niche) — built on demand.

Design of record: [`.plans/up-tier/05-data-export.md`](../.plans/up-tier/05-data-export.md)
(gitignored). This doc is the operational summary.

## Architecture: one row builder, one formatter per format

```
GET /exports?format=…&preset=…   (ExportsController — Current.account only, whitelisted params)
        │
        ▼
Exports::Ledger.new(account, from:, to:)      →  rows (light structs, find_each batches)
  ├─ Exports::CsvFormatter    →  text/csv           (stdlib CSV)
  ├─ Exports::XlsxFormatter   →  …spreadsheetml…    (caxlsx)
  └─ Exports::PdfFormatter    →  application/pdf    (prawn + prawn-table)
```

- **`Exports::Ledger`** is the single row source: `account.transactions.posted.kept` on the
  **`occurred_on`** axis (what a person means by "January"), with `billing_month` riding
  along as its own labelled column (card users need both). Amounts are **signed cents**:
  income `+`, expense/transfer `−` (a transfer leaves the source account). Category names
  are history snapshots — they survive the category's soft delete.
- **Money** stays integer cents until the last moment, then `Exports.money` →
  `BigDecimal(cents)/100`. Never floats — with one documented exception: the XLSX cell type
  is `:float` because caxlsx casts numeric cells via `to_f` internally; that is the XLSX
  file format itself, and doubles are cent-exact at any realistic magnitude. Our code hands
  it BigDecimal (see the `CELL_TYPES` comment in `xlsx_formatter.rb`).

## The pt-BR CSV gotcha (`;` + BOM)

A pt-BR Excel expects **`;`** as the CSV field delimiter (`,` is the decimal separator
there); en gets a plain `,`. The **UTF-8 BOM is emitted for both locales** — the data
carries acentos ("Alimentação") regardless of the viewer's UI language, and Excel needs the
BOM to decode them. This is the single most common "my export is garbled" bug. XLSX
sidesteps it entirely, which is why XLSX is the default offered format.

## Formula-injection guard (CSV)

A CSV cell starting with `=`, `+`, `-`, `@`, TAB or CR executes as a formula when opened in
Excel/LibreOffice — and description/merchant, category name, and account/card nickname are
user-controlled text (household members share an account). `CsvFormatter.guard` prefixes a
`'` on those three columns when the first character is a trigger. The **amount column is
never guarded** — its legitimate negatives must stay bare numbers. XLSX is safe by
construction: user text lands in string-typed cells, never formulas.

## Totals semantics: transfers are neutral

The XLSX totals block and the PDF summary show **labelled figures**, not one conflated net:

- **Entradas** — sum of income rows
- **Saídas** — sum of expense rows
- **Transferências** — sum of transfer rows
- **Resultado = entradas − saídas** — transfers excluded

An internal transfer moves money between the account's own pockets; the hub treats it as
neutral (`MonthSummary` counts savings via *guardado*), so it must not deflate the number a
person reconciles against the hub. Labels live at `exports.ledger.totals.*` in both locale
files; the PDF's bold line is `exports.pdf.net_total`.

## Delivery: sync `send_data` (decision D11)

Exports build in-request and stream via `send_data` — personal-finance data is modest
(thousands of rows a year), and the Ledger reads in `find_each` batches, never an unbounded
load. Async + email delivery (background job → Active Storage file → mailer link) is
**deferred until a real export times out**. The UI is a small form on the transactions hub:
format (XLSX default) + range presets (mês atual · últimos 3 meses · ano · tudo ·
personalizado); unknown presets fall back to the current month.

## Gems added

- `caxlsx` — XLSX builder; `caxlsx_rails` — registers the `:xlsx` Mime type
- `prawn` + `prawn-table` — the PDF extrato, pure Ruby (deliberately no system dependency
  like wkhtmltopdf). Helvetica is a Windows-1252 font, so user text is transliterated
  defensively (emoji in WhatsApp-captured merchants are dropped, not crashed on).
- CSV is the stdlib `csv` gem (already declared — required explicitly on Ruby 3.4).
