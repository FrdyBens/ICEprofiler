import os
import json
import time
import uuid
from flask import Flask, request, jsonify, render_template_string, make_response

app = Flask(__name__)

MASTER_SECRET = os.environ.get("SEVELR_SECRET", "CHANGE_THIS_TO_A_SECURE_RANDOM_PASSWORD_12345")
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
os.makedirs(DATA_DIR, exist_ok=True)
STATE_FILE = os.path.join(DATA_DIR, "state.json")

server_state = {
    "last_seen": 0,
    "agent_info": {},
    "projects": {},
    "project_runtime": {},
    "pending_actions": [],
    "action_results": {},
    "activity_logs": []
}

def load_state():
    global server_state
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                saved = json.load(f)
                server_state["projects"] = saved.get("projects", {})
        except Exception:
            pass

def save_state():
    try:
        with open(STATE_FILE, "w") as f:
            json.dump({"projects": server_state["projects"]}, f, indent=2)
    except Exception:
        pass

load_state()

def is_authenticated(req):
    auth_key = req.cookies.get("sevelr_session") or req.headers.get("X-Sevelr-Secret")
    return auth_key == MASTER_SECRET

# --- 1. Root: Serves Stealth Blank Page or Dashboard on Bare URL ---
@app.route("/", methods=["GET"])
def index():
    if not is_authenticated(request):
        # Stealth blank page with hidden key listener
        return render_template_string(STEALTH_BLANK_HTML), 200

    return render_template_string(DASHBOARD_HTML)

# --- 2. Stealth Authentication API ---
@app.route("/api/auth", methods=["POST"])
def auth():
    data = request.get_json(force=True) or {}
    key = data.get("key", "").strip()
    
    if key == MASTER_SECRET:
        resp = jsonify({"status": "authenticated"})
        resp.set_cookie("sevelr_session", MASTER_SECRET, max_age=86400*30, httponly=True, samesite="Strict", path="/")
        return resp
    
    time.sleep(1) # Anti-bruteforce delay
    return jsonify({"error": "invalid"}), 403

@app.route("/api/logout", methods=["POST"])
def logout():
    resp = jsonify({"status": "logged_out"})
    resp.delete_cookie("sevelr_session", path="/")
    return resp

# --- 3. Windows Agent Sync Endpoint ---
@app.route("/api/agent/sync", methods=["POST"])
def agent_sync():
    if request.headers.get("X-Sevelr-Secret") != MASTER_SECRET:
        return jsonify({"error": "unauthorized"}), 403

    payload = request.get_json(force=True) or {}
    now = time.time()
    server_state["last_seen"] = now
    server_state["agent_info"] = payload.get("agent_info", {})
    server_state["project_runtime"] = payload.get("runtime", {})
    
    client_projects = payload.get("projects", {})
    for p_id, p_data in client_projects.items():
        if p_id not in server_state["projects"]:
            server_state["projects"][p_id] = p_data
            save_state()

    results = payload.get("action_results", {})
    for a_id, res in results.items():
        server_state["action_results"][a_id] = res

    new_logs = payload.get("logs", [])
    if new_logs:
        server_state["activity_logs"].extend(new_logs)
        server_state["activity_logs"] = server_state["activity_logs"][-100:]

    actions_to_send = list(server_state["pending_actions"])
    server_state["pending_actions"].clear()

    return jsonify({
        "status": "ok",
        "projects": server_state["projects"],
        "actions": actions_to_send
    })

# --- 4. Dashboard Web APIs ---
@app.route("/api/state", methods=["GET"])
def get_state():
    if not is_authenticated(request):
        return jsonify({"error": "unauthorized"}), 403
    
    is_online = (time.time() - server_state["last_seen"]) < 8
    return jsonify({
        "online": is_online,
        "last_seen": server_state["last_seen"],
        "agent_info": server_state["agent_info"],
        "projects": server_state["projects"],
        "runtime": server_state["project_runtime"],
        "logs": server_state["activity_logs"][-40:],
        "action_results": server_state["action_results"]
    })

@app.route("/api/action", methods=["POST"])
def queue_action():
    if not is_authenticated(request):
        return jsonify({"error": "unauthorized"}), 403

    data = request.get_json(force=True)
    action_type = data.get("type")
    action_id = str(uuid.uuid4())[:8]

    action_obj = {
        "action_id": action_id,
        "type": action_type,
        "timestamp": time.time(),
        "payload": data.get("payload", {})
    }

    if action_type in ["save_config", "create_project"]:
        p = data["payload"]["project"]
        p_id = p["project"]["id"]
        server_state["projects"][p_id] = p
        save_state()
    elif action_type == "delete_project":
        p_id = data["payload"]["id"]
        server_state["projects"].pop(p_id, None)
        server_state["project_runtime"].pop(p_id, None)
        save_state()

    server_state["pending_actions"].append(action_obj)
    return jsonify({"status": "queued", "action_id": action_id})


# --- 5. Stealth Blank Page with Secret Trigger ---
STEALTH_BLANK_HTML = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title></title>
    <style>
        body { background: #000; margin: 0; height: 100vh; display: flex; align-items: center; justify-content: center; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
        .hidden-box { display: none; background: #111827; border: 1px solid #374151; border-radius: 12px; padding: 24px; width: 320px; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.7); text-align: center; }
        input { width: 100%; background: #030712; border: 1px solid #4b5563; border-radius: 8px; padding: 10px; color: #fff; font-size: 14px; box-sizing: border-box; margin-bottom: 12px; outline: none; }
        input:focus { border-color: #06b6d4; }
        button { width: 100%; background: #06b6d4; color: #000; font-weight: 700; border: none; padding: 10px; border-radius: 8px; cursor: pointer; font-size: 13px; }
        button:hover { background: #22d3ee; }
        .err { color: #ef4444; font-size: 12px; margin-top: 8px; display: none; }
    </style>
</head>
<body id="body">
    <div id="unlock-box" class="hidden-box">
        <input type="password" id="key-input" placeholder="Enter Session Key..." autocomplete="off">
        <button onclick="submitKey()">Authorize</button>
        <div id="err-msg" class="err">Invalid Access Key</div>
    </div>

    <script>
        let clicks = 0;
        let clickTimer = null;

        // Secret Trigger 1: Press '~' (Tilde) or 'Ctrl+Shift+S'
        window.addEventListener('keydown', (e) => {
            if (e.key === '`' || e.key === '~' || (e.ctrlKey && e.shiftKey && e.key === 'S')) {
                showPrompt();
            }
        });

        // Secret Trigger 2: Tap screen 3 times rapidly
        window.addEventListener('click', (e) => {
            if (e.target.id === 'body') {
                clicks++;
                clearTimeout(clickTimer);
                clickTimer = setTimeout(() => { clicks = 0; }, 800);
                if (clicks >= 3) {
                    showPrompt();
                    clicks = 0;
                }
            }
        });

        function showPrompt() {
            const box = document.getElementById('unlock-box');
            box.style.display = 'block';
            document.getElementById('key-input').focus();
        }

        async function submitKey() {
            const key = document.getElementById('key-input').value.trim();
            const err = document.getElementById('err-msg');
            err.style.display = 'none';

            try {
                const res = await fetch('/api/auth', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key: key })
                });

                if (res.ok) {
                    window.location.reload();
                } else {
                    err.style.display = 'block';
                }
            } catch (e) {
                err.style.display = 'block';
            }
        }

        document.getElementById('key-input').addEventListener('keydown', (e) => {
            if (e.key === 'Enter') submitKey();
        });
    </script>
</body>
</html>
"""

# --- 6. Main Dashboard HTML ---
DASHBOARD_HTML = """
<!DOCTYPE html>
<html lang="en" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sevelr Cloud Command Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            darkMode: 'class',
            theme: {
                extend: {
                    colors: {
                        brand: { 500: '#06b6d4', 600: '#0891b2' },
                        dark: { 800: '#111827', 900: '#0b0f19', 950: '#030712' }
                    }
                }
            }
        }
    </script>
    <style>
        body { background-color: #030712; color: #f3f4f6; font-family: ui-sans-serif, system-ui, sans-serif; }
        .custom-scrollbar::-webkit-scrollbar { width: 6px; }
        .custom-scrollbar::-webkit-scrollbar-track { background: #0b0f19; }
        .custom-scrollbar::-webkit-scrollbar-thumb { background: #1f2937; border-radius: 4px; }
    </style>
</head>
<body class="min-h-screen flex flex-col justify-between">

    <header class="border-b border-gray-800 bg-dark-900/80 backdrop-blur sticky top-0 z-40">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex flex-col md:flex-row md:items-center md:justify-between gap-4">
            <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-lg bg-gradient-to-tr from-cyan-500 to-indigo-600 flex items-center justify-center font-black text-black text-lg shadow-lg shadow-cyan-500/20">
                    S
                </div>
                <div>
                    <h1 class="text-xl font-black tracking-tight text-white flex items-center gap-2">
                        SEVELR <span class="text-xs font-bold px-2 py-0.5 rounded bg-cyan-950 border border-cyan-800 text-cyan-400">v2.0 Cloud</span>
                    </h1>
                    <p class="text-xs text-gray-400">Universal Windows Isolation Command Center</p>
                </div>
            </div>

            <div class="flex items-center gap-3">
                <div id="agent-status-pill" class="flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-semibold bg-gray-900 border border-gray-800 text-gray-400">
                    <span id="agent-dot" class="w-2 h-2 rounded-full bg-gray-500"></span>
                    <span id="agent-text">Connecting to Agent...</span>
                </div>

                <button onclick="openCreateModal()" class="bg-cyan-500 hover:bg-cyan-400 text-black font-bold px-4 py-2 rounded-lg text-xs flex items-center gap-1.5 shadow-lg shadow-cyan-500/10 transition active:scale-95">
                    + New Project
                </button>

                <button onclick="toggleLogsDrawer()" class="bg-gray-800 hover:bg-gray-700 text-gray-200 px-3 py-2 rounded-lg text-xs font-semibold flex items-center gap-1.5 border border-gray-700 transition">
                    Live Logs
                </button>

                <button onclick="lockSession()" class="bg-dark-950 hover:bg-rose-950 text-gray-400 hover:text-rose-400 px-3 py-2 rounded-lg text-xs font-semibold border border-gray-800 transition" title="Lock & Return to Blank Page">
                    🔒 Lock
                </button>
            </div>
        </div>
    </header>

    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 flex-1 w-full">
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-8">
            <div class="bg-dark-900 border border-gray-800/80 rounded-xl p-4">
                <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Total Projects</span>
                <p class="text-2xl font-black text-white mt-1" id="stat-total">0</p>
            </div>
            <div class="bg-dark-900 border border-gray-800/80 rounded-xl p-4">
                <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Running Instances</span>
                <p class="text-2xl font-black text-emerald-400 mt-1" id="stat-running">0</p>
            </div>
            <div class="bg-dark-900 border border-gray-800/80 rounded-xl p-4">
                <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Security State</span>
                <p class="text-2xl font-black text-cyan-400 mt-1">Enforced</p>
            </div>
            <div class="bg-dark-900 border border-gray-800/80 rounded-xl p-4">
                <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Host Agent</span>
                <p class="text-xs font-mono text-gray-300 mt-2 truncate" id="stat-host">Windows Client</p>
            </div>
        </div>

        <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-bold text-white flex items-center gap-2">
                Application Isolation Profiles
                <span id="project-count-badge" class="text-xs bg-gray-800 text-gray-300 px-2 py-0.5 rounded-full">0</span>
            </h2>
            <span class="text-xs text-gray-500">Auto-syncs live</span>
        </div>

        <div id="projects-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"></div>
    </main>

    <!-- Configure Modal -->
    <div id="edit-modal" class="fixed inset-0 bg-black/80 backdrop-blur-sm hidden flex items-center justify-center p-4 z-50">
        <div class="bg-dark-900 border border-gray-800 rounded-2xl max-w-xl w-full p-6 shadow-2xl overflow-hidden">
            <div class="flex justify-between items-start mb-4 pb-3 border-b border-gray-800">
                <div>
                    <h3 class="text-lg font-bold text-white" id="modal-title">Configure Project</h3>
                    <p class="text-xs text-gray-400">Manage isolation rules, URLs, and allowed sites</p>
                </div>
                <button onclick="closeModal('edit-modal')" class="text-gray-400 hover:text-white">&times;</button>
            </div>

            <input type="hidden" id="edit-id">
            
            <div class="space-y-4 text-sm max-h-[70vh] overflow-y-auto pr-1 custom-scrollbar">
                <div>
                    <label class="block text-xs font-semibold text-gray-300 mb-1">Launch Target URL</label>
                    <input id="edit-url" type="text" class="w-full bg-dark-950 border border-gray-800 rounded-lg p-2.5 text-white font-mono text-xs focus:border-cyan-500 focus:outline-none" placeholder="https://github.com">
                </div>

                <div>
                    <div class="flex justify-between items-center mb-1">
                        <label class="text-xs font-semibold text-gray-300">Allowed Domains</label>
                        <span class="text-[11px] text-gray-500">One per line / wildcards supported</span>
                    </div>

                    <div class="flex flex-wrap gap-1.5 mb-2">
                        <button onclick="addPreset('github')" class="text-[10px] bg-gray-800 hover:bg-gray-700 text-cyan-300 px-2 py-0.5 rounded border border-gray-700">+ GitHub</button>
                        <button onclick="addPreset('google')" class="text-[10px] bg-gray-800 hover:bg-gray-700 text-cyan-300 px-2 py-0.5 rounded border border-gray-700">+ Google</button>
                        <button onclick="addPreset('ai')" class="text-[10px] bg-gray-800 hover:bg-gray-700 text-cyan-300 px-2 py-0.5 rounded border border-gray-700">+ Claude/ChatGPT</button>
                        <button onclick="addPreset('youtube')" class="text-[10px] bg-gray-800 hover:bg-gray-700 text-cyan-300 px-2 py-0.5 rounded border border-gray-700">+ YouTube</button>
                    </div>

                    <textarea id="edit-domains" rows="6" class="w-full bg-dark-950 border border-gray-800 rounded-lg p-2.5 font-mono text-xs text-cyan-400 focus:border-cyan-500 focus:outline-none" placeholder="github.com&#10;*.github.com"></textarea>
                </div>

                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label class="block text-xs font-semibold text-gray-300 mb-1">Security Mode</label>
                        <select id="edit-mode" class="w-full bg-dark-950 border border-gray-800 rounded-lg p-2.5 text-xs text-white focus:border-cyan-500 focus:outline-none">
                            <option value="balanced">Balanced (Recommended)</option>
                            <option value="strict">Strict (Kernel Firewall)</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-xs font-semibold text-gray-300 mb-1">Disposable Profile</label>
                        <select id="edit-temp" class="w-full bg-dark-950 border border-gray-800 rounded-lg p-2.5 text-xs text-white focus:border-cyan-500 focus:outline-none">
                            <option value="false">Persistent Profile</option>
                            <option value="true">Purge on Exit</option>
                        </select>
                    </div>
                </div>
            </div>

            <div class="flex justify-end items-center gap-3 mt-6 pt-4 border-t border-gray-800">
                <button onclick="closeModal('edit-modal')" class="px-4 py-2 rounded-lg text-gray-400 hover:text-white text-xs font-semibold">Cancel</button>
                <button id="save-btn" onclick="saveProjectConfig()" class="bg-cyan-500 hover:bg-cyan-400 text-black px-5 py-2 rounded-lg text-xs font-bold transition">Save & Sync to Windows</button>
            </div>
        </div>
    </div>

    <!-- Create Modal -->
    <div id="create-modal" class="fixed inset-0 bg-black/80 backdrop-blur-sm hidden flex items-center justify-center p-4 z-50">
        <div class="bg-dark-900 border border-gray-800 rounded-2xl max-w-md w-full p-6 shadow-2xl">
            <h3 class="text-lg font-bold text-white mb-1">Create Isolated Project</h3>
            <p class="text-xs text-gray-400 mb-4">Initializes a new isolated environment on your Windows host</p>

            <div class="space-y-4 text-sm">
                <div>
                    <label class="block text-xs font-semibold text-gray-300 mb-1">Project ID / Name</label>
                    <input id="create-id" type="text" class="w-full bg-dark-950 border border-gray-800 rounded-lg p-2.5 text-white font-mono text-xs focus:border-cyan-500 focus:outline-none" placeholder="e.g. trading, github, research">
                </div>
                <div>
                    <label class="block text-xs font-semibold text-gray-300 mb-1">Template</label>
                    <select id="create-template" class="w-full bg-dark-950 border border-gray-800 rounded-lg p-2.5 text-xs text-white focus:border-cyan-500 focus:outline-none">
                        <option value="balanced">Balanced (No Admin required)</option>
                        <option value="strict">Strict (OS Kernel Firewall)</option>
                        <option value="temporary">Temporary (Disposable)</option>
                    </select>
                </div>
                <div>
                    <label class="block text-xs font-semibold text-gray-300 mb-1">Initial Target URL</label>
                    <input id="create-url" type="text" class="w-full bg-dark-950 border border-gray-800 rounded-lg p-2.5 text-white font-mono text-xs focus:border-cyan-500 focus:outline-none" placeholder="https://">
                </div>
            </div>

            <div class="flex justify-end gap-3 mt-6 pt-4 border-t border-gray-800">
                <button onclick="closeModal('create-modal')" class="px-4 py-2 rounded-lg text-gray-400 hover:text-white text-xs font-semibold">Cancel</button>
                <button onclick="submitCreateProject()" class="bg-cyan-500 hover:bg-cyan-400 text-black px-5 py-2 rounded-lg text-xs font-bold transition">Create Project</button>
            </div>
        </div>
    </div>

    <!-- Logs Drawer -->
    <div id="logs-drawer" class="fixed inset-y-0 right-0 max-w-lg w-full bg-dark-950 border-l border-gray-800 p-6 z-50 transform translate-x-full transition-transform duration-300 ease-in-out flex flex-col justify-between shadow-2xl">
        <div>
            <div class="flex justify-between items-center pb-4 border-b border-gray-800">
                <h3 class="text-sm font-bold text-white flex items-center gap-2">
                    <span class="w-2 h-2 rounded-full bg-cyan-400 animate-pulse"></span>
                    Windows Activity Logs
                </h3>
                <button onclick="toggleLogsDrawer()" class="text-gray-400 hover:text-white">&times;</button>
            </div>
            <div id="logs-container" class="mt-4 font-mono text-[11px] text-gray-300 space-y-1.5 max-h-[78vh] overflow-y-auto custom-scrollbar pr-2">
                <p class="text-gray-500 italic">Listening for live Windows agent events...</p>
            </div>
        </div>
    </div>

    <div id="toast" class="fixed bottom-6 right-6 bg-gray-900 border border-cyan-500 text-white px-4 py-3 rounded-xl shadow-2xl text-xs font-semibold hidden flex items-center gap-2 z-50">
        <span id="toast-msg">Action completed!</span>
    </div>

    <script>
        let currentProjects = {};
        let currentRuntime = {};

        async function refreshDashboard() {
            try {
                const res = await fetch('/api/state');
                if (res.status === 403) {
                    window.location.reload();
                    return;
                }
                const data = await res.json();

                const dot = document.getElementById('agent-dot');
                const text = document.getElementById('agent-text');
                const pill = document.getElementById('agent-status-pill');

                if (data.online) {
                    dot.className = 'w-2 h-2 rounded-full bg-emerald-400 animate-pulse';
                    text.innerText = 'Agent Connected';
                    text.className = 'text-emerald-400';
                    pill.className = 'flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-semibold bg-emerald-950/40 border border-emerald-800';
                } else {
                    dot.className = 'w-2 h-2 rounded-full bg-amber-400';
                    text.innerText = 'Agent Offline';
                    text.className = 'text-amber-400';
                    pill.className = 'flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-semibold bg-amber-950/40 border border-amber-800';
                }

                currentProjects = data.projects || {};
                currentRuntime = data.runtime || {};
                
                const pKeys = Object.keys(currentProjects);
                document.getElementById('stat-total').innerText = pKeys.length;
                document.getElementById('project-count-badge').innerText = pKeys.length;
                
                const runningCount = Object.values(currentRuntime).filter(r => r.status === 'running').length;
                document.getElementById('stat-running').innerText = runningCount;

                if (data.agent_info?.hostname) {
                    document.getElementById('stat-host').innerText = `${data.agent_info.hostname}`;
                }

                renderProjects();
                renderLogs(data.logs || []);
            } catch (err) { }
        }

        function renderProjects() {
            const grid = document.getElementById('projects-grid');
            grid.innerHTML = '';

            const keys = Object.keys(currentProjects);
            if (keys.length === 0) {
                grid.innerHTML = `
                    <div class="col-span-full text-center py-20 bg-dark-900 border border-gray-800/80 rounded-2xl">
                        <h4 class="text-sm font-bold text-white">No Isolated Profiles Found</h4>
                        <p class="text-xs text-gray-500 mt-1 mb-4">Create your first environment to get started.</p>
                        <button onclick="openCreateModal()" class="bg-cyan-500 text-black px-4 py-1.5 rounded-lg text-xs font-bold">+ Create Project</button>
                    </div>
                `;
                return;
            }

            keys.forEach(id => {
                const p = currentProjects[id];
                const rt = currentRuntime[id] || { status: 'stopped' };
                const isRunning = rt.status === 'running';
                
                const domains = p.network?.allowedDomains || [];
                const url = p.application?.initialUrl || 'about:blank';
                const mode = p.security?.mode || 'balanced';

                const card = document.createElement('div');
                card.className = `bg-dark-900 border ${isRunning ? 'border-emerald-500/60 shadow-lg shadow-emerald-500/5' : 'border-gray-800/80'} rounded-2xl p-5 flex flex-col justify-between transition hover:border-gray-700`;

                card.innerHTML = `
                    <div>
                        <div class="flex justify-between items-start">
                            <div>
                                <h3 class="font-bold text-base text-white capitalize flex items-center gap-2">
                                    ${id}
                                    ${isRunning ? '<span class="w-2 h-2 rounded-full bg-emerald-400 animate-ping"></span>' : ''}
                                </h3>
                                <p class="text-[11px] text-gray-400 mt-0.5 truncate max-w-[200px]">${url}</p>
                            </div>
                            <span class="text-[10px] font-bold px-2 py-0.5 rounded uppercase ${mode === 'strict' ? 'bg-rose-950 border border-rose-800 text-rose-300' : 'bg-cyan-950 border border-cyan-800 text-cyan-300'}">
                                ${mode}
                            </span>
                        </div>

                        <div class="mt-4 flex items-center justify-between p-2.5 rounded-xl bg-dark-950 border border-gray-800/70 text-xs">
                            <span class="text-gray-400">Process State:</span>
                            <span class="font-bold font-mono ${isRunning ? 'text-emerald-400' : 'text-gray-500'}">
                                ${isRunning ? `● RUNNING (PID ${rt.pid || 'Active'})` : '○ IDLE (STOPPED)'}
                            </span>
                        </div>

                        <div class="mt-4">
                            <div class="flex justify-between items-center text-[11px] font-semibold text-gray-400 uppercase tracking-wider mb-1.5">
                                <span>Allowed Sites</span>
                                <span class="text-cyan-400 font-mono">${domains.length}</span>
                            </div>
                            <div class="flex flex-wrap gap-1 max-h-20 overflow-y-auto custom-scrollbar">
                                ${domains.length > 0 ? domains.slice(0, 5).map(d => `<span class="bg-dark-950 border border-gray-800 text-cyan-300 px-2 py-0.5 rounded text-[10px] font-mono">${d}</span>`).join('') : '<span class="text-[11px] text-gray-500 italic">No domains allowlisted</span>'}
                                ${domains.length > 5 ? `<span class="text-[10px] text-gray-500 self-center">+${domains.length - 5} more</span>` : ''}
                            </div>
                        </div>
                    </div>

                    <div class="mt-6 pt-4 border-t border-gray-800/80 flex items-center gap-2">
                        ${isRunning ? `
                            <button onclick="stopProject('${id}')" class="flex-1 bg-rose-600 hover:bg-rose-500 text-white font-bold py-2 rounded-xl text-xs transition">
                                ⏹ Stop
                            </button>
                        ` : `
                            <button onclick="launchProject('${id}')" class="flex-1 bg-emerald-500 hover:bg-emerald-400 text-black font-bold py-2 rounded-xl text-xs transition">
                                ▶ Launch Browser
                            </button>
                        `}
                        <button onclick="openEditModal('${id}')" class="bg-gray-800 hover:bg-gray-700 text-gray-200 px-3 py-2 rounded-xl text-xs font-semibold border border-gray-700 transition">
                            Edit
                        </button>
                        <button onclick="deleteProject('${id}')" class="bg-gray-800/40 hover:bg-rose-950 text-gray-400 hover:text-rose-400 px-2.5 py-2 rounded-xl text-xs border border-gray-800 transition">
                            🗑
                        </button>
                    </div>
                `;
                grid.appendChild(card);
            });
        }

        function renderLogs(logs) {
            const container = document.getElementById('logs-container');
            if (logs.length === 0) return;
            container.innerHTML = logs.map(l => {
                const isSec = l.includes("SECURITY") || l.includes("Blocked") || l.includes("Drop");
                const color = isSec ? "text-rose-400" : (l.includes("Launch") ? "text-emerald-400" : "text-gray-300");
                return `<div class="p-1 rounded hover:bg-gray-900 truncate ${color}">${escapeHtml(l)}</div>`;
            }).join('');
        }

        function escapeHtml(str) {
            return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        }

        function openEditModal(id) {
            const p = currentProjects[id] || {};
            document.getElementById('edit-id').value = id;
            document.getElementById('modal-title').innerText = `Configure '${id}'`;
            document.getElementById('edit-url').value = p.application?.initialUrl || '';
            document.getElementById('edit-domains').value = (p.network?.allowedDomains || []).join('\\n');
            document.getElementById('edit-mode').value = p.security?.mode || 'balanced';
            document.getElementById('edit-temp').value = (p.privacy?.clearOnExit) ? 'true' : 'false';
            document.getElementById('edit-modal').classList.remove('hidden');
        }

        function openCreateModal() {
            document.getElementById('create-id').value = '';
            document.getElementById('create-url').value = 'https://';
            document.getElementById('create-modal').classList.remove('hidden');
        }

        function closeModal(modalId) {
            document.getElementById(modalId).classList.add('hidden');
        }

        function toggleLogsDrawer() {
            const drawer = document.getElementById('logs-drawer');
            drawer.classList.toggle('translate-x-full');
        }

        function addPreset(type) {
            const area = document.getElementById('edit-domains');
            let current = area.value.trim().split('\\n').filter(Boolean);
            const presets = {
                github: ['github.com', '*.github.com', '*.githubusercontent.com'],
                google: ['google.com', '*.google.com', '*.gstatic.com', '*.googleapis.com'],
                ai: ['claude.ai', '*.claude.ai', 'anthropic.com', 'chatgpt.com', 'openai.com', '*.oaistatic.com'],
                youtube: ['youtube.com', '*.youtube.com', '*.googlevideo.com', '*.ytimg.com']
            };
            const toAdd = presets[type] || [];
            current = [...new Set([...current, ...toAdd])];
            area.value = current.join('\\n');
        }

        async function saveProjectConfig() {
            const id = document.getElementById('edit-id').value;
            const url = document.getElementById('edit-url').value.trim();
            const domains = document.getElementById('edit-domains').value
                .split(/[\\n,]/)
                .map(s => s.trim().toLowerCase())
                .filter(Boolean);
            const mode = document.getElementById('edit-mode').value;
            const isTemp = document.getElementById('edit-temp').value === 'true';

            const proj = currentProjects[id] || {
                schemaVersion: 2,
                project: { id: id, displayName: id, template: mode },
                application: { provider: "brave" },
                network: { mode: "allowlist" },
                security: {}
            };

            proj.application = proj.application || { provider: "brave" };
            proj.application.initialUrl = url || 'about:blank';
            proj.network = proj.network || { mode: "allowlist", allowedPorts: [80, 443], allowHttp: true, allowHttps: true };
            proj.network.allowedDomains = [...new Set(domains)];
            proj.security = proj.security || {};
            proj.security.mode = mode;
            proj.privacy = proj.privacy || {};
            proj.privacy.clearOnExit = isTemp;

            await fetch('/api/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    type: "save_config",
                    payload: { project: proj }
                })
            });

            closeModal('edit-modal');
            showToast(`Saved and synced rules for '${id}'!`);
            refreshDashboard();
        }

        async function submitCreateProject() {
            const rawId = document.getElementById('create-id').value.trim();
            const cleanId = rawId.toLowerCase().replace(/[^a-z0-9_-]/g, '');
            if (!cleanId) {
                alert("Please enter a valid project name.");
                return;
            }

            const template = document.getElementById('create-template').value;
            const url = document.getElementById('create-url').value.trim() || 'about:blank';

            const newProject = {
                schemaVersion: 2,
                project: { id: cleanId, displayName: cleanId, template: template },
                application: { provider: "brave", initialUrl: url },
                network: { mode: "allowlist", allowedDomains: [], allowedPorts: [80, 443], allowHttp: true, allowHttps: true },
                filesystem: { encrypted: true, downloads: "isolated", temporaryFiles: "isolated" },
                process: { monitor: true, singleInstancePerProject: true, maxMemoryMb: 4096 },
                security: { mode: template, failClosed: template === 'strict', tamperDetection: true }
            };

            await fetch('/api/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    type: "create_project",
                    payload: { project: newProject }
                })
            });

            closeModal('create-modal');
            showToast(`Created project '${cleanId}'. Syncing to Windows...`);
            refreshDashboard();
        }

        async function launchProject(id) {
            await fetch('/api/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: "launch", payload: { id: id } })
            });
            showToast(`Launching '${id}' on Windows...`);
        }

        async function stopProject(id) {
            await fetch('/api/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: "stop", payload: { id: id } })
            });
            showToast(`Stopping '${id}'...`);
        }

        async function deleteProject(id) {
            if (!confirm(`Delete project '${id}'?`)) return;
            await fetch('/api/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: "delete_project", payload: { id: id } })
            });
            showToast(`Deleted '${id}'.`);
            refreshDashboard();
        }

        async function lockSession() {
            await fetch('/api/logout', { method: 'POST' });
            window.location.reload();
        }

        function showToast(msg) {
            const toast = document.getElementById('toast');
            document.getElementById('toast-msg').innerText = msg;
            toast.classList.remove('hidden');
            setTimeout(() => toast.classList.add('hidden'), 3500);
        }

        refreshDashboard();
        setInterval(refreshDashboard, 3000);
    </script>
</body>
</html>
"""

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
