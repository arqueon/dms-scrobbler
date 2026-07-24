import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("lastfmScrobbler.pythonCheck", ["sh", "-c", "command -v python3"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": "Python 3 is required",
                "details": "Install Python 3 and re-enable DMS Last.fm Scrobbler."
            });
        });
    }
}
