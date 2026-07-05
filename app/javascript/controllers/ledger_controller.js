import { Controller } from "@hotwired/stimulus"

// The Movimentos list: client-side text search (over merchant / category / account text baked
// into each row's data-search) and a List ⇄ Categories view switch. No server round-trip.
export default class extends Controller {
  static targets = [
    "search", "searchBox", "filters", "listView", "categoryView", "viewBtn",
    "row", "group", "noResults",
  ]

  filter() {
    const q = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""

    this.rowTargets.forEach((row) => {
      row.hidden = q !== "" && !(row.dataset.search || "").includes(q)
    })

    // Collapse a day group once all of its rows are filtered out.
    this.groupTargets.forEach((group) => {
      const anyVisible = group.querySelectorAll("[data-ledger-target='row']:not([hidden])").length > 0
      group.hidden = !anyVisible
    })

    if (this.hasNoResultsTarget) {
      const anyRow = this.rowTargets.some((row) => !row.hidden)
      this.noResultsTarget.hidden = anyRow || q === ""
    }
  }

  showList() {
    this.setView("list")
  }

  showCategory() {
    this.setView("category")
  }

  setView(view) {
    const isList = view === "list"
    if (this.hasListViewTarget) this.listViewTarget.hidden = !isList
    if (this.hasCategoryViewTarget) this.categoryViewTarget.hidden = isList
    if (this.hasSearchBoxTarget) this.searchBoxTarget.hidden = !isList
    if (this.hasFiltersTarget) this.filtersTarget.hidden = !isList

    this.viewBtnTargets.forEach((btn) => {
      const active = btn.dataset.view === view
      btn.classList.toggle("btn-primary", active)
      btn.classList.toggle("btn-ghost", !active)
    })
  }
}
