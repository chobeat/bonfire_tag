defmodule Bonfire.Tags.Acts.Tag do
  alias Bonfire.Epics
  # alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic

  alias Bonfire.Social.Tags
  alias Bonfire.Common.Utils
  alias Ecto.Changeset
  import Epics
  use Arrows

  def run(epic, act) do
    on = Keyword.get(act.options, :on, :post)
    changeset = epic.assigns[on]
    current_user = epic.assigns[:options][:current_user]

    cond do
      epic.errors != [] ->
        maybe_debug(
          epic,
          act,
          length(epic.errors),
          "Skipping due to epic errors"
        )

        epic

      is_nil(on) or not is_atom(on) ->
        maybe_debug(epic, act, on, "Skipping due to `on` option")
        epic

      not (is_struct(current_user) or is_binary(current_user)) ->
        maybe_debug(
          epic,
          act,
          current_user,
          "Skipping due to missing current_user"
        )

        epic

      not is_struct(changeset) || changeset.__struct__ != Changeset ->
        maybe_debug(epic, act, changeset, "Skipping :#{on} due to changeset")
        epic

      changeset.action not in [:insert, :upsert, :delete] ->
        maybe_debug(
          epic,
          act,
          changeset.action,
          "Skipping, no matching action on changeset"
        )

        epic

      changeset.action in [:insert, :upsert] ->
        boundary = epic.assigns[:options][:boundary]
        attrs_key = Keyword.get(act.options, :attrs, :post_attrs)
        attrs = Keyword.get(epic.assigns[:options], attrs_key, %{})

        categories_auto_boost =
          Utils.e(changeset, :changes, :post_content, :changes, :mentions, [])
          |> Tags.maybe_boostable_categories(current_user, ...)

        # |> maybe_debug(epic, act, ..., "categories_auto_boost")

        maybe_debug(epic, act, "tags", "Casting")

        changeset
        |> Tags.cast(attrs, current_user, boundary)
        |> Epic.assign(epic, on, ...)
        |> Epic.assign(..., :categories_auto_boost, categories_auto_boost)

      changeset.action == :delete ->
        # TODO: deletion
        epic
    end
  end
end
