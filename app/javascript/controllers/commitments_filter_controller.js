import { Controller } from "@hotwired/stimulus"

// The Compromissos list: client-side search + category / instrument filters. Active rows carry
// their searchable text, category id, instrument token and amount in data attributes; filtering
// hides rows, folds kind groups that end up empty and swaps the top total for the selection's
// sum. Archived rows are not targets, so they never join the filtered total.
export default class extends Controller {
  static targets = ["search", "category", "instrument", "row", "group", "noResults",
                    "totalLabel", "totalValue", "filterButton", "clearButton", "filterDot"]

  connect() {
    this.updateChrome()
  }

  // Reset the sheet filters (category + instrument) and re-filter. Search is its own control.
  clear() {
    if (this.hasCategoryTarget) this.categoryTarget.value = ""
    if (this.hasInstrumentTarget) this.instrumentTarget.value = ""
    this.apply()
  }

  apply() {
    const q = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    const category = this.hasCategoryTarget ? this.categoryTarget.value : ""
    const instrument = this.hasInstrumentTarget ? this.instrumentTarget.value : ""
    const active = q !== "" || category !== "" || instrument !== ""

    let visible = 0
    let cents = 0
    this.rowTargets.forEach((row) => {
      const match =
        (q === "" || (row.dataset.search || "").includes(q)) &&
        (category === "" || row.dataset.category === category) &&
        (instrument === "" || row.dataset.instrument === instrument)
      row.hidden = !match
      if (match) {
        visible += 1
        cents += Number(row.dataset.amount || 0)
      }
    })

    this.groupTargets.forEach((group) => {
      const anyVisible = group.querySelectorAll("[data-commitments-filter-target='row']:not([hidden])").length > 0
      group.hidden = !anyVisible
    })

    if (this.hasNoResultsTarget) this.noResultsTarget.hidden = visible > 0

    if (this.hasTotalLabelTarget && this.hasTotalValueTarget) {
      this.totalLabelTarget.textContent = active
        ? this.totalLabelTarget.dataset.labelFiltered
        : this.totalLabelTarget.dataset.labelAll
      this.totalValueTarget.textContent = this.format(
        active ? cents : Number(this.totalValueTarget.dataset.totalCents || 0)
      )
    }

    this.updateChrome()
  }

  // The Filtros button reflects the sheet filters (category / instrument), not the search box:
  // it goes primary with a dot, and the toolbar clear (×) shows, when either is set.
  updateChrome() {
    const on = (this.hasCategoryTarget && this.categoryTarget.value !== "") ||
               (this.hasInstrumentTarget && this.instrumentTarget.value !== "")
    if (this.hasFilterButtonTarget) this.filterButtonTarget.classList.toggle("text-primary", on)
    if (this.hasFilterDotTarget) this.filterDotTarget.hidden = !on
    if (this.hasClearButtonTarget) this.clearButtonTarget.hidden = !on
  }

  format(cents) {
    const locale = document.documentElement.lang || "pt-BR"
    return new Intl.NumberFormat(locale, { style: "currency", currency: "BRL" }).format(cents / 100)
  }
}
