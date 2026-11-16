#!/usr/bin/env python3
"""Add a bounded archive reader to an existing pinned BoxedWine distribution."""
from pathlib import Path
import argparse,shutil

def prepare(runtime):
    source=Path(__file__).resolve().parents[1]/'Engines/Web/http-range-file.js'
    shell=runtime/'boxedwine-shell.js';text=shell.read_text()
    hook='            }else if(Config.appZipFile.length > 0){\n'
    assert text.count(hook)==1, 'Unexpected upstream app loader; review before patching'
    text=text.replace(hook,hook+'''                if (getParameter("app-range") === "true") {
                    // The native importer verifies a flat archive with its executable
                    // at the root. Do not read the whole ZIP to guess a subfolder.
                    TonTonRangeFile.mount(FS, "/" + Config.appZipFile,
                        Config.locateAppBaseUrl + Config.appZipFile).then(callback).catch(function(error) {
                            console.error("Unable to mount game archive: " + error);
                            const status = document.getElementById("status");
                            if (status) status.textContent = "资源读取失败：" + error;
                        });
                    return;
                }
''')
    html=runtime/'boxedwine.html';markup=html.read_text();needle='<script src=boxedwine-shell.js>'
    assert markup.count(needle)==1
    html.write_text(markup.replace(needle,'<script src=http-range-file.js></script>'+needle))
    shell.write_text(text);shutil.copyfile(source,runtime/'http-range-file.js')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('runtime',type=Path);a=p.parse_args();prepare(a.runtime)
