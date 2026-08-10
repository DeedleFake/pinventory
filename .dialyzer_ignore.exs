# Dialyxir ignore list (Elixir term format).
#
# Ecto.Multi is opaque and stores a MapSet. Dialyzer treats Multi.new/0 as a
# concrete struct and reports call_without_opaque on Multi.insert/update/run.
# That is a known ecosystem false positive, not a bug in app code.
[
  {"lib/pinventory/items.ex", :call_without_opaque},
  {"lib/pinventory/locations.ex", :call_without_opaque}
]
