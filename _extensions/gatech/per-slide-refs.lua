-- per-slide-refs.lua
--
-- Pandoc Lua filter. Splits the document into reveal.js slides at level-1
-- and level-2 headers, collects the [@cite] keys used on each slide, and
-- appends an `aside` div holding the CSL-rendered bibliography entries for
-- those keys to the end of that slide.
--
-- Entries are harvested by running citeproc on a copy of the document; the
-- input document is otherwise returned unchanged, so Quarto's own citeproc
-- pass still drives inline citation styling, hover popups, and the
-- end-of-deck bibliography.
--
-- Aside entries are compacted before insertion: italicized container titles
-- listed in `citation-abbrev.lua` are replaced with their abbreviation, and
-- `pp.`/`vol.`/`no.`/`doi:`/`Available:` tails are dropped.
--
-- Top-level `Div.fragment` blocks have their citations emitted in a matching
-- `.fragment` aside carrying the same `data-fragment-index`, so reveal.js
-- reveals each reference together with the fragment that introduced it;
-- citations outside any fragment go in a base, always-visible aside.
-- Documents with no citations are returned unchanged.

-- Quarto cross-references (`@thm-foo`, `@fig-bar`, ...) are still Cite
-- elements when this filter runs. They must not reach citeproc, which would
-- look them up in the bibliography and warn "citation ... not found".
local crossref_prefixes = {
  fig = true, tbl = true, lst = true, eq = true, sec = true,
  thm = true, lem = true, cor = true, prp = true, cnj = true,
  def = true, exm = true, exr = true, sol = true, rem = true, alg = true,
  nte = true, tip = true, wrn = true, imp = true, cau = true,
}

local function is_crossref(id)
  local prefix = id:match('^(%a+)%-')
  return prefix ~= nil and crossref_prefixes[prefix] == true
end

-- Copy of `doc` with cross-reference keys removed from every Cite; a Cite
-- left with no bibliography keys is dropped entirely.
local function without_crossrefs(doc)
  return doc:walk({
    Cite = function(c)
      local kept = pandoc.List({})
      for _, cit in ipairs(c.citations) do
        if not is_crossref(cit.id) then kept:insert(cit) end
      end
      if #kept == #c.citations then return nil end
      if #kept == 0 then return {} end
      c.citations = kept
      return c
    end,
  })
end

local function has_citations(doc)
  local found = false
  doc:walk({
    Cite = function(c)
      for _, cit in ipairs(c.citations) do
        if not is_crossref(cit.id) then found = true end
      end
      return c
    end,
  })
  return found
end

-- The abbreviation table ships alongside this filter inside the extension.
local function abbrev_path()
  if quarto and quarto.utils and quarto.utils.resolvePath then
    local ok, path = pcall(quarto.utils.resolvePath, 'citation-abbrev.lua')
    if ok and path then return path end
  end
  -- Fallback for invoking the filter directly with pandoc.
  local dir = PANDOC_SCRIPT_FILE and PANDOC_SCRIPT_FILE:match('(.*[/\\])') or ''
  return dir .. 'citation-abbrev.lua'
end

local function load_abbrev()
  local ok, tbl = pcall(dofile, abbrev_path())
  if ok and type(tbl) == 'table' then return tbl end
  return {}
end

local abbrev = {}
local refs = {}

local function harvest_refs(blocks)
  for _, blk in ipairs(blocks) do
    if blk.tag == 'Div' then
      if blk.identifier == 'refs' then
        for _, child in ipairs(blk.content) do
          if child.tag == 'Div' and child.identifier:sub(1, 4) == 'ref-' then
            refs[child.identifier:sub(5)] = child
          end
        end
        return true
      end
      if harvest_refs(blk.content) then return true end
    end
  end
  return false
end

local function collect_cites(blk)
  local ids, seen = {}, {}
  pandoc.walk_block(blk, {
    Cite = function(c)
      for _, cit in ipairs(c.citations) do
        if not seen[cit.id] then
          seen[cit.id] = true
          table.insert(ids, cit.id)
        end
      end
    end,
  })
  return ids
end

-- Names to bold in citations; set from `bold-authors` in Pandoc().
local bold_names = {}

local function lua_escape(s)
  return (s:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1'))
end

local function transform_md(md)
  md = md:gsub('[\r\n]+', ' '):gsub('%s+', ' ')

  -- Abbreviate italicized container titles. Match any `*...*` span whose
  -- contents contain the key phrase; replace whole span with `*<abbrev>*`.
  for _, pair in ipairs(abbrev) do
    local pat = '%*[^%*]*' .. lua_escape(pair[1]) .. '[^%*]*%*'
    md = md:gsub(pat, '*' .. pair[2] .. '*')
  end

  -- Strip `[Online]. ` prefix if present, then strip `Available: <url>` tail
  -- through end of entry (IEEE CSL emits this for URL-bearing entries).
  md = md:gsub('%s*%[Online%]%.?%s*', ' ')
  md = md:gsub('[%.,]?%s*Available:.*$', '')

  -- Strip `, doi: ...` / `. doi: ...` through end of entry (doi is always last).
  md = md:gsub('[%.,]?%s*[dD][oO][iI]:.*$', '')

  -- Strip `, pp. X-Y` (or `p. X`), `, vol. X`, `, no. Y`. `[^,%.]*` stops
  -- at the next comma or period so we don't swallow the year that follows.
  md = md:gsub(',?%s*pp?%.[^,%.]*', '')
  md = md:gsub(',?%s*vol%.[^,%.]*', '')
  md = md:gsub(',?%s*no%.[^,%.]*', '')

  -- Drop the "in" that precedes a container title (` in *Title*` -> ` *Title*`).
  md = md:gsub('%sin%s+%*', ' *')

  -- Drop standalone publisher "IEEE" (redundant for IEEE venues).
  md = md:gsub(',%s*IEEE%s*,', ',')
  md = md:gsub(',%s*IEEE%s*%.', '.')

  -- Bold the names listed under `bold-authors` in the document metadata.
  -- Longest first, via placeholders, so a name that is a substring of another
  -- listed name is not bolded twice.
  local marks = {}
  for i, name in ipairs(bold_names) do
    md = md:gsub(lua_escape(name), function()
      table.insert(marks, '**' .. name .. '**')
      return '\0' .. #marks .. '\0'
    end)
  end
  md = md:gsub('%z(%d+)%z', function(i) return marks[tonumber(i)] end)

  md = md:gsub('%s+$', '')
  if md ~= '' and not md:match('[%.%?!]$') then md = md .. '.' end
  return md
end

local function transform_inlines(inlines)
  local md = pandoc.write(
    pandoc.Pandoc({ pandoc.Plain(pandoc.Inlines(inlines)) }),
    'markdown'
  )
  md = transform_md(md)
  local parsed = pandoc.read(md, 'markdown')
  if parsed.blocks[1] and parsed.blocks[1].content then
    return parsed.blocks[1].content
  end
  return inlines
end

local function has_class(classes, name)
  for _, c in ipairs(classes) do
    if c == name then return true end
  end
  return false
end

-- CSL entries come through as a Div.csl-entry whose children are a single
-- Para holding two inline Spans: .csl-left-margin ("[n]") and
-- .csl-right-inline (the rendered reference text). We transform the inline
-- content of the right-inline span in place.
local function transform_csl_entry(ref)
  local new_content = pandoc.List({})
  for _, blk in ipairs(ref.content) do
    if (blk.tag == 'Para' or blk.tag == 'Plain') and blk.content then
      local new_inlines = pandoc.List({})
      for _, il in ipairs(blk.content) do
        if il.tag == 'Span' and has_class(il.classes, 'csl-right-inline') then
          local transformed = transform_inlines(il.content)
          new_inlines:insert(pandoc.Span(
            transformed,
            pandoc.Attr('', il.classes, il.attributes)
          ))
        else
          new_inlines:insert(il)
        end
      end
      if blk.tag == 'Para' then
        new_content:insert(pandoc.Para(new_inlines))
      else
        new_content:insert(pandoc.Plain(new_inlines))
      end
    else
      new_content:insert(blk)
    end
  end
  -- Rebuild the csl-entry without its id so the DOM doesn't end up with
  -- two elements sharing ref-<key> (hover lookups use getElementById).
  return pandoc.Div(new_content, pandoc.Attr('', ref.classes, {}))
end

local function build_aside(keys, frag_idx)
  local entries = {}
  for _, k in ipairs(keys) do
    local ref = refs[k]
    if ref then table.insert(entries, transform_csl_entry(ref)) end
  end
  if #entries == 0 then return nil end
  local classes = { 'aside' }
  local attrs = {}
  if frag_idx ~= nil then
    table.insert(classes, 'fragment')
    attrs['data-fragment-index'] = tostring(frag_idx)
  end
  return pandoc.Div(entries, pandoc.Attr('', classes, attrs))
end

-- Fragment-aware emission. Quarto pre-processes `. . .` pauses and
-- `:::{.fragment}` divs into `Div.fragment` blocks before user filters
-- run. For each top-level `Div.fragment` on a slide, assign a unique
-- `data-fragment-index`, harvest citations inside, and emit a matching
-- `.fragment` aside with the same index — reveal.js reveals each
-- citation in sync with the fragment that introduced it. Citations
-- outside any fragment go in a base (always-visible) aside.
local function emit_slide(slide, out)
  local frag_counter = 0
  local base_keys, base_seen = {}, {}
  local frag_groups = {}

  for _, blk in ipairs(slide) do
    if blk.tag == 'Div' and has_class(blk.classes, 'fragment') then
      -- Respect an explicit user-supplied fragment-index. Only auto-assign
      -- when the Div carries no index — otherwise we'd clobber the order
      -- the slide author specified and the citation aside would reveal
      -- out of sync.
      local explicit = blk.attributes['data-fragment-index']
        or blk.attributes['fragment-index']
      local idx
      if explicit then
        idx = tonumber(explicit) or frag_counter
      else
        idx = frag_counter
        frag_counter = frag_counter + 1
      end

      -- Rebuild the Div with data-fragment-index baked into its Attr so
      -- the attribute reliably makes it into the HTML (mutating
      -- `.attributes` in place isn't always safe for every Div).
      local new_attrs = {}
      for k, v in pairs(blk.attributes) do new_attrs[k] = v end
      new_attrs['data-fragment-index'] = tostring(idx)
      local new_blk = pandoc.Div(
        blk.content,
        pandoc.Attr(blk.identifier, blk.classes, new_attrs)
      )

      local keys, seen = {}, {}
      for _, k in ipairs(collect_cites(new_blk)) do
        if not base_seen[k] and not seen[k] then
          seen[k] = true
          table.insert(keys, k)
        end
      end
      table.insert(frag_groups, { idx = idx, keys = keys })
      table.insert(out, new_blk)
    else
      for _, k in ipairs(collect_cites(blk)) do
        if not base_seen[k] then
          base_seen[k] = true
          table.insert(base_keys, k)
        end
      end
      table.insert(out, blk)
    end
  end

  local base_aside = build_aside(base_keys, nil)
  if base_aside then table.insert(out, base_aside) end
  for _, g in ipairs(frag_groups) do
    local aside = build_aside(g.keys, g.idx)
    if aside then table.insert(out, aside) end
  end
end

function Pandoc(doc)
  if not has_citations(doc) then return doc end
  abbrev = load_abbrev()

  bold_names = {}
  local meta_names = doc.meta['bold-authors']
  if meta_names then
    if pandoc.utils.type(meta_names) ~= 'List' then meta_names = { meta_names } end
    for _, n in ipairs(meta_names) do
      table.insert(bold_names, pandoc.utils.stringify(n))
    end
    table.sort(bold_names, function(a, b) return #a > #b end)
  end

  -- Run citeproc on a copy to harvest CSL-rendered entries.
  -- The original `doc` stays untouched so Quarto's own citeproc pass
  -- still processes inline citations (hover popups, styled [1] links,
  -- end-of-deck bibliography).
  local rendered = pandoc.utils.citeproc(without_crossrefs(doc))
  harvest_refs(rendered.blocks)

  local out, slide, in_slide = {}, {}, false

  local function flush()
    if in_slide then emit_slide(slide, out) end
    slide = {}
  end

  for _, blk in ipairs(doc.blocks) do
    if blk.tag == 'Header' and (blk.level == 1 or blk.level == 2) then
      flush()
      table.insert(out, blk)
      in_slide = true
    elseif in_slide then
      table.insert(slide, blk)
    else
      table.insert(out, blk)
    end
  end
  flush()

  doc.blocks = out
  return doc
end
