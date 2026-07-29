const MESSAGE = "You have unsaved changes. Leave this page?"

const UnsavedChanges = {
  mounted() {
    this.allowNext = false
    this.syncFromEl()

    this.onBeforeUnload = (event) => {
      if (!this.dirty || this.allowNext) return
      event.preventDefault()
      event.returnValue = MESSAGE
    }

    this.onClick = (event) => {
      if (!this.dirty || this.allowNext) return
      if (event.defaultPrevented) return
      if (event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

      const link = event.target.closest("a[href]")
      if (!link) return
      if (link.target === "_blank" || link.hasAttribute("download")) return
      if (!this.isLeavingPage(link)) return

      if (!window.confirm(MESSAGE)) {
        event.preventDefault()
        event.stopImmediatePropagation()
        return
      }

      // User accepted leave; do not warn again for this navigation.
      this.allowNext = true
      this.dirty = false
    }

    window.addEventListener("beforeunload", this.onBeforeUnload)
    document.addEventListener("click", this.onClick, true)

    // Keep push_event contract for immediate client updates between patches.
    this.handleEvent("unsaved-changes", ({dirty}) => {
      this.dirty = !!dirty
      this.allowNext = false
    })
  },

  updated() {
    this.syncFromEl()
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    document.removeEventListener("click", this.onClick, true)
  },

  syncFromEl() {
    // Do not re-enable warnings after the user confirmed leave.
    if (this.allowNext) return
    this.dirty = this.el.dataset.dirty === "true"
  },

  isLeavingPage(link) {
    const url = new URL(link.href, window.location.href)
    if (url.origin !== window.location.origin) return true

    return (
      url.pathname !== window.location.pathname ||
      url.search !== window.location.search
    )
  }
}

export default UnsavedChanges
