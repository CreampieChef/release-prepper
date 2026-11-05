* Tracker icons: the registry (`lib/feature/tracker_icon.dart`) has one entry,
  for PornoLab, and `Tracker` has one value, so there is no other tracker to add
  an icon for yet. A tracker with no asset draws a placeholder, so this is
  actionable only when another tracker is added.
* Open Release: a folder that does not exist, or a `release.json` that cannot be
  read, is reported as the file not being there. The content of the manifest is
  checked and reported as a failure of its own; what is left is to tell the two
  apart, and to give the menu item a busy or disabled state while the picker and
  the load are in flight.
* Validation for the subsite and site fields: the shape of the two domains. The
  rule engine reports an unfilled required field and the date shape only, so this
  needs a problem kind of its own.
* Renamed files: the record ID is the relative path, so a rename loses the record
  and its URLs. Moving the data to the new name is not built; the app accepts the
  data is gone.
* Validation for the other release types, per tracker, and how many posters a
  release may have. Only the single video field list states rules, so nothing is
  checked for the others, and the required set a tracker wants is not known until
  more release types are covered.
* bbcode in description and additional information. The renderer emits the value
  as it is; bbcode appears only because the `text` style rule is empty.
* Validation of description templates and style files: every style slot a
  template uses is defined, and every bbcode tag a style rule uses is in the
  tracker's whitelist. A style that does not define a slot renders its content
  unchanged, and there is no whitelist.
* An image with no `thumb_url` is skipped by the message block, which is the
  right behaviour only when it cannot happen. Showing an error for it is not
  built.
* Lock the source folder field once records exist, so re-picking a folder cannot
  change the paths that are the record IDs. Re-picking the same folder does
  nothing; a different folder loses the records and their URLs.
* Editor: a button that fills the release-level tags from the items.
  One-directional on purpose — editing a release field must not overwrite the
  items it was built from.
