#!/usr/bin/env python3
import os
import sys

def patch_file(path, old, new):
    if not os.path.exists(path):
        print(f"Skipping {path} (not found)")
        return
    with open(path, "r", encoding="utf-8") as f:
        data = f.read()
    crlf = "\r\n" in data
    data_uni = data.replace("\r\n", "\n")
    if new in data_uni:
        print(f"Already patched: {path}")
        return
    if old not in data_uni:
        print(f"Target pattern not found in {path}")
        return
    data_uni = data_uni.replace(old, new, 1)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(data_uni.replace("\n", "\r\n") if crlf else data_uni)
    print(f"Successfully patched: {path}")

base = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# 1. cupsonline.go
path_cups = os.path.join(base, "core", "transport", "cupsonline", "cupsonline.go")
old_auth = """func authorize(ctx context.Context, roomURL string, session *http.Client) (*cupsAuth, error) {
\tclient := session
\tif client == nil {
\t\tjar, _ := cookiejar.New(nil)
\t\tclient = &http.Client{
\t\t\tJar:     jar,
\t\t\tTimeout: 30 * time.Second,
\t\t\tCheckRedirect: func(req *http.Request, via []*http.Request) error {
\t\t\t\tif len(via) >= 5 {
\t\t\t\t\treturn fmt.Errorf("too many redirects")
\t\t\t\t}
\t\t\t\treturn nil
\t\t\t},
\t\t}
\t}"""

new_auth = """func authorize(ctx context.Context, roomURL string, session *http.Client) (*cupsAuth, error) {
\tclient := session
\tif client == nil {
\t\tjar, _ := cookiejar.New(nil)
\t\ttr := &http.Transport{
\t\t\tDialContext:         netbind.DialContext,
\t\t\tDisableKeepAlives:   true,
\t\t\tForceAttemptHTTP2:   false,
\t\t\tTLSHandshakeTimeout: 10 * time.Second,
\t\t}
\t\tclient = &http.Client{
\t\t\tJar:       jar,
\t\t\tTimeout:   20 * time.Second,
\t\t\tTransport: tr,
\t\t\tCheckRedirect: func(req *http.Request, via []*http.Request) error {
\t\t\t\tif len(via) >= 5 {
\t\t\t\t\treturn fmt.Errorf("too many redirects")
\t\t\t\t}
\t\t\t\treturn nil
\t\t\t},
\t\t}
\t}"""

old_stop_cups = """func (t *CupsonlineTransport) Stop() error {
\tt.cancel()
\tt.SetConnected(false)
\tif st := t.stripe.Load(); st != nil {
\t\t_ = st.Stop()
\t}
\treturn t.BaseTransport.Stop()
}"""

new_stop_cups = """func (t *CupsonlineTransport) Stop() error {
\tt.cancel()
\tt.SetConnected(false)
\tfor _, ws := range t.wss {
\t\tif c := ws.currentConn(); c != nil {
\t\t\t_ = c.WriteControl(websocket.CloseMessage,
\t\t\t\twebsocket.FormatCloseMessage(websocket.CloseNormalClosure, "disconnect"),
\t\t\t\ttime.Now().Add(300*time.Millisecond))
\t\t\t_ = c.Close()
\t\t}
\t}
\tif st := t.stripe.Load(); st != nil {
\t\t_ = st.Stop()
\t}
\tif tr, ok := http.DefaultTransport.(*http.Transport); ok {
\t\ttr.CloseIdleConnections()
\t}
\treturn t.BaseTransport.Stop()
}"""

patch_file(path_cups, old_auth, new_auth)
patch_file(path_cups, old_stop_cups, new_stop_cups)

# 2. mobile.go
path_mobile = os.path.join(base, "core", "mobile", "mobile.go")
old_m_import = '\t"encoding/json"\n\t"fmt"'
new_m_import = '\t"encoding/json"\n\t"fmt"\n\t"net/http"'

old_m_stop = """\tif trans != nil {
\t\t_ = trans.Stop()
\t}
}"""
new_m_stop = """\tif trans != nil {
\t\t_ = trans.Stop()
\t}
\tif tr, ok := http.DefaultTransport.(*http.Transport); ok {
\t\ttr.CloseIdleConnections()
\t}
}"""

patch_file(path_mobile, old_m_import, new_m_import)
patch_file(path_mobile, old_m_stop, new_m_stop)

# 3. proxy.go
path_proxy = os.path.join(base, "core", "mobile", "proxy.go")
old_p_import = '\t"fmt"\n\t"strings"'
new_p_import = '\t"fmt"\n\t"net/http"\n\t"strings"'
old_p_stop = """\tif stream != nil {
\t\tstream.Stop()
\t}
}"""
new_p_stop = """\tif stream != nil {
\t\tstream.Stop()
\t}
\tif tr, ok := http.DefaultTransport.(*http.Transport); ok {
\t\ttr.CloseIdleConnections()
\t}
}"""

patch_file(path_proxy, old_p_import, new_p_import)
patch_file(path_proxy, old_p_stop, new_p_stop)

# 4. streamnet.go
path_streamnet = os.path.join(base, "core", "tunnel", "streamnet.go")
old_s_stop = """func (n *StreamNet) Stop() error {
\tn.stopOnce.Do(func() {
\t\tn.stack.Close()
\t\tif n.mux != nil {
\t\t\t_ = n.mux.Close()
\t\t}
\t})
\treturn nil
}"""
new_s_stop = """func (n *StreamNet) Stop() error {
\tn.stopOnce.Do(func() {
\t\tn.stack.Close()
\t\tif n.mux != nil {
\t\t\t_ = n.mux.Close()
\t\t} else if n.carrier != nil {
\t\t\t_ = n.carrier.Stop()
\t\t}
\t})
\treturn nil
}"""

patch_file(path_streamnet, old_s_stop, new_s_stop)

print("Core patching done.")
