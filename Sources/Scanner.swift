import Foundation

/// One dev server — `npm start`, `npx next dev`, `vite`, … — and the ports its process tree listens on.
struct DevServer: Identifiable, Equatable {
    let id: pid_t            // pid of the process that started it
    let directory: String    // folder holding the package.json
    let packageName: String?
    let label: String        // how it was started: "npm start", "npx next dev", "vite"
    let command: String?     // what actually runs: the package.json script body, or the CLI's own command line
    let ports: [Int]
    let startedAt: Date

    var primaryPort: Int? { ports.first }
    var name: String { URL(fileURLWithPath: directory).lastPathComponent }
    /// The package.json name, when it says something the folder name doesn't (e.g. "acme-storefront" in ~/code/shop).
    var distinctPackageName: String? {
        guard let packageName, packageName.split(separator: "/").last.map(String.init) != name else { return nil }
        return packageName
    }
}

enum Scanner {
    private struct Proc {
        let pid: pid_t
        let ppid: pid_t
        let comm: String
        let startedAt: Date
    }

    // MARK: - Scan

    static func scan() -> [DevServer] {
        let procs = allProcesses()
        var children: [pid_t: [pid_t]] = [:]
        for p in procs where p.pid != p.ppid { children[p.ppid, default: []].append(p.pid) }

        var roots: [pid_t: (proc: Proc, invocation: Invocation)] = [:]
        for p in procs where candidateComms.contains(p.comm) {
            if let inv = parse(arguments(of: p.pid)) { roots[p.pid] = (p, inv) }
        }
        // `npm run dev` → `next dev`: the script is the server, not its CLI. Drop a root when something
        // stronger (script > runner > CLI) started it, so it's listed once, under the name you typed.
        let parent = Dictionary(procs.map { ($0.pid, $0.ppid) }, uniquingKeysWith: { a, _ in a })
        for (pid, root) in roots {
            var cur = parent[pid], hops = 0
            while let c = cur, c > 1, hops < 64 {
                if let above = roots[c], above.invocation.kind.rawValue > root.invocation.kind.rawValue {
                    roots[pid] = nil
                    break
                }
                cur = parent[c]; hops += 1
            }
        }

        var servers: [DevServer] = []
        for (pid, root) in roots {
            // Ports belong to the nearest script runner above them, so a wrapper like
            // `"dev": "bun run dev:web & bun run dev:api"` (or turbo fanning out to `npm run dev`s) doesn't swallow its children.
            var owned: [pid_t] = [pid]
            var hasNestedRoot = false
            var stack = children[pid] ?? []
            var seen: Set<pid_t> = [pid]
            while let c = stack.popLast() {
                guard seen.insert(c).inserted else { continue }
                if roots[c] != nil { hasNestedRoot = true; continue }
                owned.append(c)
                stack += children[c] ?? []
            }
            let ports = Array(Set(owned.flatMap(listeningPorts))).sorted()
            if ports.isEmpty && hasNestedRoot { continue }

            var dir = currentDirectory(of: pid) ?? "/"
            if let cwd = root.invocation.cwd {
                dir = URL(fileURLWithPath: cwd, relativeTo: URL(fileURLWithPath: dir, isDirectory: true)).standardizedFileURL.path
            }
            let pkg = packageInfo(near: dir)
            servers.append(DevServer(
                id: pid,
                directory: pkg?.directory ?? dir,
                packageName: pkg?.name,
                label: root.invocation.label,
                command: root.invocation.script.flatMap { pkg?.scripts[$0] } ?? root.invocation.commandLine,
                ports: ports,
                startedAt: root.proc.startedAt
            ))
        }
        return servers.sorted { ($0.primaryPort ?? .max, $0.id) < ($1.primaryPort ?? .max, $1.id) }
    }

    // MARK: - Kill

    /// SIGTERM the whole tree (package managers don't always forward signals to the server they spawned),
    /// then SIGKILL whatever is still alive after a grace period. Blocks; call off the main thread.
    static func kill(rootPid: pid_t, grace: TimeInterval = 3) {
        let procs = allProcesses()
        guard let root = procs.first(where: { $0.pid == rootPid }),
              candidateComms.contains(root.comm), parse(arguments(of: rootPid)) != nil else { return }

        var children: [pid_t: [pid_t]] = [:]
        for p in procs where p.pid != p.ppid { children[p.ppid, default: []].append(p.pid) }
        var tree: [pid_t] = []
        var queue = [rootPid]
        var seen: Set<pid_t> = []
        while !queue.isEmpty {
            let pid = queue.removeFirst()
            guard pid > 1, seen.insert(pid).inserted else { continue }
            tree.append(pid)
            queue += children[pid] ?? []
        }

        for pid in tree { Darwin.kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(grace)
        var alive = tree
        while !alive.isEmpty && Date() < deadline {
            usleep(100_000)
            alive = alive.filter { Darwin.kill($0, 0) == 0 }
        }
        for pid in alive { Darwin.kill(pid, SIGKILL) }
    }

    // MARK: - Command line parsing

    struct Invocation: Equatable {
        enum Kind: Int { case cli = 0, runner = 1, script = 2 }   // precedence when they nest
        let kind: Kind
        let label: String          // "npm start", "npx next dev", "vite"
        let script: String?        // the package.json script, for script runs
        let commandLine: String?   // the CLI and its arguments, for runners and direct CLIs
        let cwd: String?
    }

    /// Kernel process names worth reading argv for. npm, npx and classic yarn run as `node`; pnpm and bun are native.
    private static let candidateComms: Set<String> = ["bun", "bunx", "node", "npm", "npx", "pnpm", "yarn"]

    /// Script names that usually mean "a server is running": dev, start, serve, preview, develop — plus dev:web, start-prod, …
    private static let serverScripts = ["dev", "develop", "start", "serve", "preview"]

    /// Dev-server CLIs and the subcommands that start a server. An empty set means the bare command serves
    /// (`vite`, `serve`), except for the subcommands in `notServing`.
    private static let devCLIs: [String: Set<String>] = [
        "next": ["dev"], "nuxt": ["dev"], "nuxi": ["dev"], "astro": ["dev", "preview"], "remix": ["dev"],
        "svelte-kit": ["dev"], "react-scripts": ["start"], "webpack": ["serve"], "ng": ["serve"],
        "vue-cli-service": ["serve"], "expo": ["start"], "gatsby": ["develop"], "docusaurus": ["start"],
        "wrangler": ["dev"], "vercel": ["dev"], "netlify": ["dev"], "storybook": ["dev"], "rsbuild": ["dev", "preview"],
        "rspack": ["dev", "serve"], "vinxi": ["dev"],
        "vite": [], "webpack-dev-server": [], "parcel": [], "serve": [], "http-server": [], "live-server": [],
        "nodemon": [], "start-storybook": [],
    ]
    private static let notServing: Set<String> = ["build", "optimize", "test", "lint", "help", "--help", "-h", "--version", "-v"]

    /// `npm exec next dev` shows up as "npx next dev", and so on.
    private static let runnerLabels: [String: [String: String]] = [
        "npm": ["exec": "npx", "x": "npx"], "pnpm": ["exec": "pnpm exec", "dlx": "pnpm dlx"],
        "yarn": ["exec": "yarn exec", "dlx": "yarn dlx"], "bun": ["x": "bunx"],
    ]

    private static let flagsWithValue: Set<String> = [
        "--cwd", "--prefix", "--dir", "-C", "--filter", "-F", "--workspace", "--env-file", "--config", "-c",
        "--preload", "-r", "--require", "--import", "--tsconfig-override", "--define", "-d", "--loader", "-l",
        "--main-fields", "--conditions", "--elide-lines", "--shell",
    ]
    private static let cwdFlags: Set<String> = ["--cwd", "--prefix", "--dir", "-C"]

    /// Recognises package scripts (`npm run dev`, `bun start`, `pnpm --dir web dev`, `yarn workspace web dev`, …),
    /// package runners (`npx next dev`, `pnpm dlx vite`, `bunx serve`, …) and dev-server CLIs run directly
    /// (`node …/node_modules/.bin/next dev`, `vite`, …).
    static func parse(_ argv: [String]) -> Invocation? {
        var tokens = argv
        // npm overwrites its argv with its process title: ["npm run dev", "", ""].
        if let first = argv.first, first.contains(" "), argv.dropFirst().allSatisfy(\.isEmpty) {
            tokens = first.split(separator: " ").map(String.init)
        }
        guard !tokens.isEmpty else { return nil }
        // `node /path/to/yarn.js dev`, `node …/node_modules/.bin/next dev`: skip the interpreter.
        let start = basename(tokens[0]) == "node" && tokens.count > 1 && !tokens[1].hasPrefix("-") ? 1 : 0

        if let manager = packageManager(tokens[start]) {
            return parseManager(manager, tokens, from: start + 1)
        }
        let head = basename(tokens[start])
        if ["npx", "pnpx", "bunx", "npx-cli.js"].contains(head) {   // npx-cli.js: npm 6's npx run through node
            return parseRunner(head == "npx-cli.js" ? "npx" : head, tokens, from: start + 1, cwd: nil)
        }
        // A dev-server CLI started directly: from node_modules when run through node, or by its own name.
        guard start == 0 || tokens[start].contains("node_modules/") else { return nil }
        return devCommand(tokens, at: start).map {
            Invocation(kind: .cli, label: $0.label, script: nil, commandLine: $0.commandLine, cwd: nil)
        }
    }

    private static func parseManager(_ manager: String, _ tokens: [String], from: Int) -> Invocation? {
        var positional: [(String, Int)] = []
        var cwd: String?
        var i = from
        while i < tokens.count && positional.count < 3 {
            let arg = tokens[i]
            i += 1
            if arg.hasPrefix("-") {
                if let eq = arg.firstIndex(of: "="), cwdFlags.contains(String(arg[..<eq])) {
                    cwd = String(arg[arg.index(after: eq)...])
                } else if flagsWithValue.contains(arg) || (manager == "npm" && arg == "-w"), i < tokens.count {
                    if cwdFlags.contains(arg) { cwd = tokens[i] }
                    i += 1
                }
                continue
            }
            positional.append((arg, i - 1))
            if positional.count == 1, let label = runnerLabels[manager]?[arg] {
                return parseRunner(label, tokens, from: i, cwd: cwd)
            }
        }

        let script: String?
        switch positional.first?.0 {
        case "run", "run-script": script = positional.dropFirst().first?.0
        case "workspace" where manager == "yarn": script = positional.dropFirst(2).first?.0
        default: script = positional.first?.0
        }
        guard let script, isServerScript(script) else { return nil }
        return Invocation(kind: .script, label: "\(manager) \(script)", script: script, commandLine: nil, cwd: cwd)
    }

    /// `npx [flags] [--] <cli> <args>`: a server only if the CLI it runs is one.
    private static func parseRunner(_ label: String, _ tokens: [String], from: Int, cwd: String?) -> Invocation? {
        var i = from
        while i < tokens.count, tokens[i].hasPrefix("-") {
            if tokens[i] == "--" { i += 1; break }
            i += ["-p", "--package", "-c", "--call"].contains(tokens[i]) ? 2 : 1
        }
        guard i < tokens.count, let cmd = devCommand(tokens, at: i) else { return nil }
        return Invocation(kind: .runner, label: "\(label) \(cmd.label)", script: nil, commandLine: cmd.commandLine, cwd: cwd)
    }

    /// Whether `tokens[at...]` starts a dev server — `next dev`, `vite`, `react-scripts start` — and how to name it.
    private static func devCommand(_ tokens: [String], at: Int) -> (label: String, commandLine: String)? {
        var cli = basename(tokens[at])
        for ext in [".js", ".cjs", ".mjs"] where cli.hasSuffix(ext) { cli.removeLast(ext.count) }
        guard let serving = devCLIs[cli] else { return nil }
        let args = Array(tokens[(at + 1)...])
        let sub = args.first { !$0.hasPrefix("-") }
        let label: String
        if serving.isEmpty {
            if let sub, notServing.contains(sub) { return nil }
            label = sub.map { ["dev", "serve", "preview", "start"].contains($0) ? "\(cli) \($0)" : cli } ?? cli
        } else {
            guard let sub, serving.contains(sub) else { return nil }
            label = "\(cli) \(sub)"
        }
        return (label, ([cli] + args).joined(separator: " "))
    }

    private static func packageManager(_ token: String?) -> String? {
        guard var name = token.map(basename) else { return nil }
        for ext in [".js", ".cjs", ".mjs"] where name.hasSuffix(ext) { name.removeLast(ext.count) }
        if name == "npm-cli" { return "npm" }
        if name.hasPrefix("yarn-") { return "yarn" }   // Yarn Berry release files: yarn-4.5.0.cjs
        return ["bun", "npm", "pnpm", "yarn"].contains(name) ? name : nil
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func isServerScript(_ name: String) -> Bool {
        serverScripts.contains { base in
            guard name.hasPrefix(base) else { return false }
            guard let next = name.dropFirst(base.count).first else { return true }
            return next == ":" || next == "-" || next == "_"
        }
    }

    // MARK: - package.json

    private struct PackageInfo {
        let name: String?
        let directory: String
        let scripts: [String: String]
    }

    private static func packageInfo(near dir: String) -> PackageInfo? {
        var url = URL(fileURLWithPath: dir, isDirectory: true)
        for _ in 0..<8 {
            let file = url.appendingPathComponent("package.json")
            if let data = try? Data(contentsOf: file),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return PackageInfo(name: name, directory: url.path, scripts: json["scripts"] as? [String: String] ?? [:])
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    // MARK: - libproc / sysctl

    private static func allProcesses() -> [Proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        size = buf.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else { return [] }
        return buf.prefix(size / MemoryLayout<kinfo_proc>.stride).map { p in
            let comm = withUnsafeBytes(of: p.kp_proc.p_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            let start = p.kp_proc.p_un.__p_starttime
            return Proc(
                pid: p.kp_proc.p_pid,
                ppid: p.kp_eproc.e_ppid,
                comm: comm,
                startedAt: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
            )
        }
    }

    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
        // Layout: argc (int32), exec path, NUL padding, argv[0..argc), env…
        let argc = buf.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }
        while i < size && buf[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < argc && i < size {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    private static func currentDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    private static func listeningPorts(of pid: pid_t) -> [Int] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bytes)
        guard used > 0 else { return [] }

        var ports: [Int] = []
        for fd in fds.prefix(Int(used) / stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var si = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, size) == size,
                  si.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = si.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            ports.append(Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))))
        }
        return ports
    }
}
