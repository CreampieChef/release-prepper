// One of the test hosters. It posts to the Python test server
// (test-hoster/rp_test_hoster.py), which answers as several hosters at once and
// tells them apart by the tag it is given. The script API cannot read the
// Server Name, so the tag is hardcoded here, and this script differs from
// rptest_b.nut only by that tag.
function UploadFile(FileName, options) {
    nm.setUrl("http://127.0.0.1/upload");
    nm.addQueryParam("tag", "rptest-a");
    nm.addQueryParam("thumb_width", options.getParam("THUMBWIDTH"));
    nm.addQueryParamFile("file", FileName, ExtractFileName(FileName), GetFileMimeType(FileName));

    nm.doUploadMultipartData();

    if (nm.responseCode() != 200) {
        WriteLog("error", "[rptest-a] Response code " + nm.responseCode() + "\r\n" + nm.errorString());
        return 0;
    }

    local result = ParseJSON(nm.responseBody());
    if (result == null) {
        WriteLog("error", "[rptest-a] Response is not JSON");
        return 0;
    }

    if (!result.success) {
        WriteLog("error", "[rptest-a] Upload failed: " + result.error);
        return 0;
    }

    options.setDeleteUrl(result.delete_url);
    options.setDirectUrl(result.direct_url);
    options.setThumbUrl(result.thumb_url);
    options.setViewUrl(result.view_url);

    return 1;
}
