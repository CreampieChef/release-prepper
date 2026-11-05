local attempts = 0;

function UploadFile(FileName, options) {

    local env_var = getenv("test")
    WriteLog("info", "env_var is " + env_var)

    if (FileName.find("fail") != null) {
        WriteLog("error", "Unknown error occured. Reason: stub image file name contained 'fail'");
        return 0;
    }

    attempts = attempts + 1;
    local attempt_string = ServerParams.getParam("successful_attempt");
    if (attempt_string != "") {
        local attempt = attempt_string.tointeger()

        if (attempt != attempts) {
            WriteLog("error", "Failed attempt. Try again.")
            return 0;
        }
    }

    local endSlash = "/"
    if (FileName.find("/") == 0) {
        endSlash = ""
    }

    options.setViewUrl("https://example.com" + endSlash + FileName + ".html");
    options.setDirectUrl("https://example.com" + endSlash + FileName);
    options.setThumbUrl("https://example.com/thumb" + endSlash + FileName);

    return 1;
}