// The second test hoster. Same server as rptest_a.nut, only a different tag — see that
// file for why the tag is hardcoded here.
function UploadFile(FileName, options) {
    nm.setUrl("http://127.0.0.1/upload");
    nm.addQueryParam("tag", "rptest-b");
    nm.addQueryParam("thumb_width", options.getParam("THUMBWIDTH"));
    nm.addQueryParamFile("file", FileName, ExtractFileName(FileName), GetFileMimeType(FileName));

    nm.doUploadMultipartData();

    if (nm.responseCode() != 200) {
        WriteLog("error", "[rptest-b] Response code " + nm.responseCode() + "\r\n" + nm.errorString());
        return 0;
    }

    local result = ParseJSON(nm.responseBody());
    if (result == null) {
        WriteLog("error", "[rptest-b] Response is not JSON");
        return 0;
    }

    if (!result.success) {
        WriteLog("error", "[rptest-b] Upload failed: " + result.error);
        return 0;
    }

    options.setDeleteUrl(result.delete_url);
    options.setDirectUrl(result.direct_url);
    options.setThumbUrl(result.thumb_url);
    options.setViewUrl(result.view_url);

    return 1;
}
