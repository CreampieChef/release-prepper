# Single video fields

The fields the Single video form has. Fields depend on the release type; the
other types have their own lists (`ai/photoset_pack.md`, `ai/video_pack.md`,
`ai/single_photoset.md`, `ai/image_folder_upload.md`). The numbers are what
`ai/doc.md` and the tests refer to; the order the form shows the fields in is
`ai/doc.md` §2.

The Russian values are the labels in `lib/l10n/app_ru.arb`, and the English file
holds their translations. Every field is a text box unless stated otherwise.

1. Path to the movie file. The row shows a file picker after the path. The label
   is "Path to video", because the same row is the source row for every type
   whose source is a file.
2. В ролях — cast.
3. Название ролика — the video title.
4. Номер на сайте (необязательно) — the site number. Optional.
5. Подсайт и сайт — subsite and site. Format validation is open work
   (`lib/TODO.MD`).
6. Дата производства — the production date, with a date picker. The value is
   `YYYY`, `YYYY-MM` or `YYYY`, and is stored as the text the field shows.
7. Жанр (теги) — genre tags. The values are the tag names as StashDB holds
   them, which are always in English; the label is translated, the values are
   not.
8. Продолжительность — duration in hh:mm:ss. Read from the movie file.
9. Тип видео — video type, for example 2160p. Read from the movie file.
10. Качество видео — video quality, for example SiteRip. The one field a new
    release starts with a value for.
11. Формат видео — video format, for example MP4. Read from the movie file.
12. Видео — the video stream line, formatted exactly as:
    `AVC, 3840x2160, 29.970 (30000/1001) FPS, 15.0 Mb/s`
13. Аудио — the audio stream line, formatted exactly as:
    `AAC LC, 48.0 kHz, 2 channels, 128 kb/s`
14. Описание — description. A multiline box that grows with the text. bbcode is
    open work (`lib/TODO.MD`).
15. Доп. информация (необязательно) — additional information. Same as 14.
16. Размер файла — file size. Read from the movie file, so the user cannot edit
    it. Stored as bytes in `release.json`, shown in a human-friendly form
    (`9.5 GiB (10737418240 bytes)`) with the byte count.

Items 8, 9, 11, 12, 13 and 16 are read from the file rather than typed, so the
rows that show them read as text rather than as inputs: the user cannot fix here
a value the file did not give. A part the probe does not report is left out
rather than guessed, so a stream line may be shorter than the example above.

The field list also names `sceneUrl`, which has no row of its own: the Stash
section is the widget that shows and edits it.
