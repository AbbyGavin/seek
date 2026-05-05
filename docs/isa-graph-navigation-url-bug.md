# ISA Temporary Sharing Links — Branch Review & Known Issues

## Feature Overview

ISA Temporary Sharing Links let managers share private Investigations, Studies, and Assays
with external collaborators via time-limited URL codes, with no login required.

URL form: `https://host/{type}/{id}?code={secure_code}`

Codes propagate **downward only** in the ISA hierarchy:
- Investigation code → all child Studies, Assays, and their leaf assets
- Study code → child Assays and their leaf assets, but NOT parent Investigation
- Assay code → leaf assets (DataFile, SOP, Model, Document) only

---

## Fixed Bug: Double `?` in Graph Node URLs

### Symptom

When visiting an ISA item via a temporary link
(`/investigations/1?code=q1a1ohCuRE0t4zAGvm...`) and clicking a node in the ISA graph,
navigation produces a malformed URL with **two `?` characters**:

```
# Bad — code param is broken
http://host/assays/1?code=q1a1ohCuRE0t4zAGvm%2F...?graph_view=split

# Also bad — graph_view encoded into the code value
http://host/assays/1?code=q1a1ohCuRE0t4zAGvm%2F...%3Fgraph_view%3Dsplit
```

The server receives a mangled `code` so `auth_by_code?` returns `false`, denying access
even though the code is valid.

### Root Cause

`app/assets/javascripts/isa_graph.js` — `visitNode` unconditionally prepended `?graph_view=`
to whatever URL was already stored in the node's `data('url')`:

```javascript
// Before fix — always uses ?, breaks when URL already has query params
var url = node.data('url') + '?graph_view=' + ISA.view.current;
```

The `fullscreen` parameter already used `&` correctly; only `graph_view` was wrong.
Both the cytoscape graph click and the jstree double-click path go through `visitNode`.

### Fix Applied

`app/assets/javascripts/isa_graph.js:282-292`:

```javascript
visitNode: function (node) {
    if (node != ISA.originNode && node.data('url')) {
        var baseUrl = node.data('url');
        var separator = baseUrl.indexOf('?') !== -1 ? '&' : '?';
        var url = baseUrl + separator + 'graph_view=' + ISA.view.current;
        if (ISA.isFullscreen()) {
            url = url + '&fullscreen';
        }
        window.location = url;
    }
},
```

---

## Known Issues & Edge Cases

### 1. `child_assays` links don't propagate `code` — Bug

**File:** `app/views/assays/show.html.erb:76-81`

When an ISA-JSON compliant assay is an assay stream (has child assays), the child assay links
are generated without the `code` parameter:

```erb
<% @assay.child_assays.map do |ca| %>
  <li>
    <%= link_to ca.title, ca %>   <%# BUG: no code param %>
  </li>
<% end %>
```

A user visiting an assay stream via temporary link cannot navigate to child assays because
the link drops the code. Child assays are downward in the hierarchy so code should propagate.

**Fix needed:**
```erb
<%= link_to ca.title, assay_path(ca, code: params[:code]) %>
```

---

### 2. `ObservationUnit` not handled in `auth_by_code?` — Functional Gap

**File:** `lib/seek/permissions/code_based_authorization.rb`

`ObservationUnit` uses `acts_as_isa` and therefore includes `CodeBasedAuthorization`, but
`auth_by_code?` has no branch for it:

```ruby
def auth_by_code?(code)
  return true if special_auth_codes.unexpired.where(code: code).exists?  # own code ✓

  if is_a?(Investigation)       # ← handled
  elsif is_a?(Study)            # ← handled
  elsif is_a?(Assay)            # ← handled
  elsif respond_to?(:assays)    # ← DataFile, SOP, Model, etc.
  end
  false  # ← ObservationUnit always falls here
end
```

`ObservationUnit` has `related_assays`, not `assays`, so the `respond_to?(:assays)` branch
does not match. Consequences:

- A Study or Investigation temporary link does **not** grant access to child `ObservationUnit`s.
- `DataFile`s attached directly to an `ObservationUnit` (not via an Assay) cannot be accessed
  via Study or Investigation codes.

No test covers this scenario. This may be an acceptable limitation for the initial scope, but
should be documented or fixed before the feature is considered complete.

**Fix needed in `auth_by_code?`:** add an `elsif is_a?(ObservationUnit)` branch that checks
the parent study and its investigation, mirroring the Assay branch.

---

### 3. `is_parent_of_current?` doesn't recognise Assay-stream hierarchy — Minor

**File:** `app/helpers/assets_helper.rb`

`is_parent_of_current?` only checks Study and Investigation as parents of an Assay:

```ruby
if current.is_a?(Assay)
  return current.study == target   if target.is_a?(Study)
  return current.investigation == target if target.is_a?(Investigation)
end
```

When viewing a child assay in an assay stream, the parent `assay_stream` node is not
recognised as a parent. Its URL in the graph will include `?code=...` unnecessarily.

This is **not a security issue** — passing an assay code to the parent assay's URL doesn't
grant access (Investigation/Study `auth_by_code?` doesn't check child codes). The URL is
just unnecessarily noisy.

---

### 4. Duplicate commit history — Review Quality

The branch has 26 commits against `main` but 11 commit messages appear twice (identical
message, different hash). This likely resulted from a force-push after a partial rebase.

Duplicated subjects:
- Enabled Sharing Links for all three ISA item types
- Added Contextual Help Text in _special_auth_code_form.html.erb
- Include code parameter in resource paths for temporary link access
- Ensure ISA show page asset links include params[:code]
- Add support for temporary links with special auth codes
- Add special auth code display to ISA show pages
- Enhance ISA graph functionality with code-based authorization
- Add tests for code-based authorization in ISA assets
- Add integration tests for temporary link functionality
- Refactor authorization code checks for special auth codes
- address copilot comments

Recommend squashing or cleaning history before merging to keep `main` readable.

---

### 5. `_special_auth_code_display` shows only the first code — UX Limitation

**File:** `app/views/assets/_special_auth_code_display.html.erb:1`

```ruby
special_auth_code = resource.special_auth_codes.first
```

If a manager creates multiple active codes (e.g., one per reviewer), only the first is shown
in the UI. The form allows creating multiple codes but the display partial doesn't list them all.

---

## Authorization Flow Reference

### `auth_by_code?(code)` — `lib/seek/permissions/code_based_authorization.rb`

| Resource | Checks |
|---|---|
| Investigation | own codes only |
| Study | own codes + parent investigation codes |
| Assay | own codes + parent study codes + parent investigation codes |
| DataFile / SOP / Model / Document | own codes + parent assay codes + assay's study + assay's investigation |
| ObservationUnit | own codes only (**gap** — parent study/investigation not checked) |

### Code inclusion in ISA graph node URLs — `app/helpers/isa_helper.rb`

`cytoscape_node_elements` includes `?code=` in a node URL only when:
- `can_view_asset?(item, code)` returns true (the code grants view access to that item), **or**
- `should_include_code_for_isa_link?(item)` returns true (the item is not a parent of the
  current page's resource, determined by `is_parent_of_current?`)

### `show_resource_path` — `app/helpers/assets_helper.rb`

The resource title link on show pages includes `?code=` when `params[:code]` is present and
the current action is not `index`.

---

## Files Changed in This Branch

| File | Change |
|---|---|
| `app/assets/javascripts/isa_graph.js` | Fixed double-`?` separator bug in `visitNode` |
| `app/controllers/assays_controller.rb` | Added `special_auth_codes_attributes` to permitted params |
| `app/controllers/investigations_controller.rb` | Same |
| `app/controllers/studies_controller.rb` | Same |
| `app/helpers/assets_helper.rb` | Added `show_resource_path` code propagation; `should_include_code_for_isa_link?`; `is_parent_of_current?`; `can_view_asset?`; `can_download_asset?` |
| `app/helpers/investigations_helper.rb` | `investigation_link` conditionally includes code |
| `app/helpers/isa_helper.rb` | `cytoscape_elements`/`cytoscape_node_elements` accept `code` param; node URLs include code for accessible children |
| `app/helpers/studies_helper.rb` | `study_link` conditionally includes code |
| `app/views/assays/manage.html.erb` | Removed `sharing_link: false` to enable sharing link UI |
| `app/views/assays/show.html.erb` | Added `special_auth_code_display` partial |
| `app/views/assets/_special_auth_code_form.html.erb` | Added contextual help text per ISA level |
| `app/views/general/_isa_graph.html.erb` | Passes `params[:code]` into `cytoscape_elements` |
| `app/views/investigations/manage.html.erb` | Removed `sharing_link: false` |
| `app/views/investigations/show.html.erb` | Added `special_auth_code_display` partial |
| `app/views/studies/manage.html.erb` | Removed `sharing_link: false` |
| `app/views/studies/show.html.erb` | Added `special_auth_code_display` partial |
| `lib/seek/isa_graph_generator.rb` | Accepts `code` param; uses it for node visibility checks |
| `lib/seek/permissions/code_based_authorization.rb` | `auth_by_code?` implements downward propagation for ISA hierarchy |
| `test/functional/assays_controller_test.rb` | Tests for `special_auth_codes_attributes` |
| `test/functional/investigations_controller_test.rb` | Same |
| `test/functional/studies_controller_test.rb` | Same |
| `test/integration/isa_special_auth_codes_access_test.rb` | End-to-end access tests for all ISA levels |
| `test/unit/code_based_authorization_test.rb` | Unit tests for `auth_by_code?` logic |
