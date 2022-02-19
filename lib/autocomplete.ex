defmodule Bonfire.Tag.Autocomplete do
  use Bonfire.Common.Utils
  alias Bonfire.Common.URIs
  alias Bonfire.Tag.Tags
  import Where

  # TODO: put in config
  @tag_terminator " "
  @tags_seperator " "
  @prefixes ["@", "&", "+"]
  @taxonomy_prefix "+"
  @search_index "public"
  @max_length 50


  def prefix_index("+" = prefix) do
    ["Bonfire.Classify.Category", "Bonfire.Tag"]
  end

  def prefix_index("@" = prefix) do
    "Bonfire.Data.Identity.User"
  end

  # def prefix_index(tag_search, "&" = prefix, consumer) do
  #   "Community"
  # end

  def prefix_index(_) do
    ["Bonfire.Data.Identity.User", "Bonfire.Classify.Category", "Bonfire.Tag"]
  end

  # FIXME combine the following functions

  def api_tag_lookup(tag_search, prefix, consumer) do
    api_tag_lookup_public(tag_search, prefix, consumer, prefix_index(prefix))
  end

  def search_prefix(tag_search, prefix) do
    search_or_lookup(tag_search, @search_index, %{"index_type" => prefix_index(prefix)})
  end

  def search_type(tag_search, type) do
    search_or_lookup(tag_search, @search_index, %{"index_type" => type})
  end

  def api_tag_lookup_public(tag_search, prefix, consumer, index_type) do
    hits = maybe_search(tag_search, %{"index_type" => index_type}) || Tags.maybe_find_tags(tag_search)

    tag_lookup_process(tag_search, hits, prefix, consumer)
  end

  def search_or_lookup(tag_search, index, facets \\ nil)

  def search_or_lookup("lt", _, _), do: nil # dirty workaround

  def search_or_lookup(tag_search, index, facets) do
    # debug("Search.search_or_lookup: #{tag_search} with facets #{inspect facets}")

    hits = maybe_search(tag_search, %{index: index}, facets)
    if hits do # use search index if available
      hits
    else
      Tags.maybe_find_tags(tag_search)
    end
  end

  def maybe_search(tag_search, opts, facets \\ nil) do
    #debug(searched: tag_search)
    #debug(facets: facets)

    if module_enabled?(Bonfire.Search) do # use search index if available
      debug("Bonfire.Tag.Autocomplete: searching #{inspect tag_search} with facets #{inspect facets}")
      search = Bonfire.Search.search(tag_search, opts, false, facets)
      # debug(searched: search)

      if(is_map(search) and Map.has_key?(search, "hits") and length(search["hits"])) do
        # search["hits"]
        Enum.map(search["hits"], &tag_hit_prepare(&1, tag_search))
        |> Utils.filter_empty()
        |> input_to_atoms()
        # |> debug(label: "maybe_search results")
      end
    end
  end

  def tag_lookup_process(tag_search, hits, prefix, consumer) do
    #debug(search["hits"])
    hits
    |> Enum.map(&tag_hit_prepare(&1, tag_search, prefix, consumer))
    |> Utils.filter_empty()
  end

  def tag_hit_prepare(hit, _tag_search, prefix, consumer) do
    # debug(hit)

    hit = stringify_keys(hit) |> debug()

    username = hit["username"] || hit["character"]["username"]

    # FIXME: do this by filtering Meili instead?
    if strlen(username) do
      %{
        "name" => e(hit, "name_crumbs", e(hit, "profile", "name", e(hit, "name", e(hit, "username", nil)))),
        "link" => e(hit, "canonical_url", URIs.canonical_url(e(hit, "id", nil)))
      }
      |> tag_add_field(consumer, prefix, (username || e(hit, "id", "")))
    end
  end

  def tag_add_field(hit, "tag_as", _prefix, as) do
    Map.merge(hit, %{tag_as: as})
  end

  def tag_add_field(hit, "ck5", prefix, as) do
    if String.at(as, 0) == prefix do
      Map.merge(hit, %{"id" => to_string(as)})
    else
      Map.merge(hit, %{"id" => prefix <> to_string(as)})
    end
  end

  # def tag_suggestion_display(hit, tag_search) do
  #   name = e(hit, "name_crumbs", e(hit, "name", e(hit, "username", nil)))

  #   if !is_nil(name) and name =~ tag_search do
  #     split = String.split(name, tag_search, parts: 2, trim: false)
  #     debug(split)
  #     [head | tail] = split

  #     List.to_string([head, "<span>", tag_search, "</span>", tail])
  #   else
  #     name
  #   end
  # end

  def find_all_tags(content) do
    #debug(prefixes: @prefixes)

    # FIXME?
    words = content |> HtmlEntities.decode() |> tags_split()
    #debug(tags_split: words)

    if words do
      # tries =
      @prefixes
      |> Enum.map(&try_tag_search(&1, words))
      # |> IO.inspect
      |> Enum.map(&filter_results(&1))
      |> List.flatten()
      |> Utils.filter_empty()
      # |> IO.inspect

      #debug(find_all_tags: tries)

    end
  end

  def filter_results(res) when is_list(res) do
    res
    |> Enum.map(&filter_results(&1))
  end
  def filter_results(%{tag_results: tag_results}) when (is_list(tag_results) and length(tag_results)>0) do
    tag_results
  end
  def filter_results(%{tag_results: tag_results}) when is_map(tag_results) do
    [tag_results]
  end
  def filter_results(_) do
    nil
  end

  ## moved from tag_autocomplete_live.ex ##

  def try_prefixes(content) do
    #debug(prefixes: @prefixes)
    # FIXME?
    tries = Enum.map(@prefixes, &try_tag_search(&1, content))
      |> Utils.filter_empty()
    #debug(try_prefixes: tries)

    List.first(tries)
  end

  def try_tag_search(tag_prefix, words) when is_list(words) do
    Enum.map(words, &try_tag_search(tag_prefix, &1))
  end

  def try_tag_search(tag_prefix, content) do

    case tag_search_from_text(content, tag_prefix) do
      search when is_binary(search) and byte_size(search) > 0 -> tag_search(search, tag_prefix)
      _ -> nil
    end
  end

  def try_tag_search(content) do
    tag_search = tag_search_from_tags(content)

    if strlen(tag_search) > 0 do
      tag_search(tag_search, @taxonomy_prefix)
    end
  end

  def tag_search(tag_search, tag_prefix) do
    tag_results = search_prefix(tag_search, tag_prefix)

    #debug(tag_prefix: tag_prefix)
    #debug(tag_results: tag_results)

    if tag_results do
      %{tag_search: tag_search, tag_results: tag_results, tag_prefix: tag_prefix}
    end
  end

  def tag_search_from_text(text, prefix) do
    parts = String.split(text, prefix, parts: 2)

    if length(parts) > 1 do
      # debug(tag_search_from_text: parts)
      typed = List.last(parts)

      if String.length(typed) > 0 and String.length(typed) < @max_length and !(typed =~ @tag_terminator) do
        typed
      end
    end
  end

  def tags_split(text) do
    parts = String.split(text, @tags_seperator)

    if length(parts) > 0 do
      parts
    end
  end

  def tag_search_from_tags(text) do
    parts = tags_split(text)

    if length(parts) > 0 do
      typed = List.last(parts)

      if String.length(typed) do
        typed
      end
    end
  end


  def tag_hit_prepare(hit, tag_search) do
    # FIXME: do this by filtering Meili instead?
    if !is_nil(hit["username"]) or !is_nil(hit["id"]) do
      hit
      |> Map.merge(%{display: tag_suggestion_display(hit, tag_search)})
      |> Map.merge(%{tag_as: e(hit, "username", e(hit, "id", ""))})
    end
  end

  def tag_suggestion_display(hit, tag_search) do
    name = e(hit, "name_crumbs", e(hit, "name", e(hit, "username", nil)))

    if !is_nil(name) and name =~ tag_search do
      split = String.split(name, tag_search, parts: 2, trim: false)
      #debug(split)
      [head | tail] = split

      List.to_string([head, "<span>", tag_search, "</span>", tail])
    else
      name
    end
  end
end
