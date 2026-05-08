import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Command Hints - Inline documentation and smart hints
/// 
/// Implements comprehensive command hints:
/// - Inline command documentation
/// - Context-aware hints
/// - Command man page integration
/// - Syntax highlighting for commands
/// - Interactive help system
class CommandHints {
  bool _isInitialized = false;
  
  // Documentation cache
  final Map<String, CommandDocumentation> _commandDocs = {};
  final Map<String, List<CommandHint>> _commandHints = {};
  final Map<String, SyntaxHighlight> _syntaxHighlights = {};
  
  // Context tracking
  final Map<String, CommandContext> _contexts = {};
  final List<String> _commandHistory = [];
  
  // Help system
  final HelpSystem _helpSystem = HelpSystem();
  
  // Configuration
  CommandHintsConfig _config = CommandHintsConfig();
  
  CommandHints();
  
  bool get isInitialized => _isInitialized;
  Map<String, CommandDocumentation> get commandDocs => Map.unmodifiable(_commandDocs);
  Map<String, List<CommandHint>> get commandHints => Map.unmodifiable(_commandHints);
  
  /// Initialize command hints
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Initialize help system
      await _helpSystem.initialize();
      
      // Load command documentation
      await _loadCommandDocumentation();
      
      // Setup syntax highlighting
      _setupSyntaxHighlighting();
      
      _isInitialized = true;
      debugPrint('💡 Command Hints initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Command Hints: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/command_hints_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = CommandHintsConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load command hints config: $e');
    }
  }
  
  /// Load command documentation
  Future<void> _loadCommandDocumentation() async {
    try {
      // Load built-in command documentation
      await _loadBuiltInDocumentation();
      
      // Load system command documentation
      await _loadSystemCommands();
      
      // Load user command documentation
      await _loadUserCommands();
      
      debugPrint('📚 Loaded ${_commandDocs.length} command documentations');
    } catch (e) {
      debugPrint('⚠️ Failed to load command documentation: $e');
    }
  }
  
  /// Load built-in documentation
  Future<void> _loadBuiltInDocumentation() async {
    final builtInCommands = {
      'git': CommandDocumentation(
        command: 'git',
        description: 'Distributed version control system',
        usage: 'git <command> [options]',
        examples: [
          'git status',
          'git add .',
          'git commit -m "message"',
          'git push origin main',
          'git pull origin main',
          'git log --oneline -10',
          'git diff --stat',
          'git branch -a',
          'git checkout -b feature-branch',
          'git merge feature-branch',
          'git rebase main',
          'git stash',
          'git stash pop',
        ],
        options: [
          CommandOption(
            name: '--help',
            description: 'Show help information',
            type: 'flag',
          ),
          CommandOption(
            name: '--version',
            description: 'Show version information',
            type: 'flag',
          ),
          CommandOption(
            name: '--verbose',
            description: 'Enable verbose output',
            type: 'flag',
            shortName: '-v',
          ),
          CommandOption(
            name: '--quiet',
            description: 'Suppress output',
            type: 'flag',
            shortName: '-q',
          ),
          CommandOption(
            name: '--git-dir',
            description: 'Set path to git repository',
            type: 'argument',
            argument: '<path>',
          ),
        ],
        subcommands: [
          Subcommand(
            name: 'status',
            description: 'Show working tree status',
            usage: 'git status [options]',
            examples: ['git status', 'git status --short', 'git status --porcelain'],
          ),
          Subcommand(
            name: 'add',
            description: 'Add file contents to index',
            usage: 'git add [options] <file>',
            examples: ['git add .', 'git add file.txt', 'git add --all'],
          ),
          Subcommand(
            name: 'commit',
            description: 'Record changes to repository',
            usage: 'git commit [options] [-m <msg>]',
            examples: ['git commit -m "Fix bug"', 'git commit --amend', 'git commit --no-edit'],
          ),
          Subcommand(
            name: 'push',
            description: 'Update remote refs',
            usage: 'git push [options] [repository] [refspec]',
            examples: ['git push origin main', 'git push --force', 'git push --all'],
          ),
          Subcommand(
            name: 'pull',
            description: 'Fetch from and integrate with another repo',
            usage: 'git pull [options] [repository] [refspec]',
            examples: ['git pull origin main', 'git pull --rebase origin main'],
          ),
          Subcommand(
            name: 'log',
            description: 'Show commit logs',
            usage: 'git log [options]',
            examples: ['git log --oneline -10', 'git log --graph --decorate', 'git log --grep="bug"'],
          ),
          Subcommand(
            name: 'diff',
            description: 'Show changes between commits',
            usage: 'git diff [options] [commit] [commit]',
            examples: ['git diff HEAD~1', 'git diff main..feature', 'git diff --stat'],
          ),
          Subcommand(
            name: 'branch',
            description: 'List, create, or delete branches',
            usage: 'git branch [options] [branch-name]',
            examples: ['git branch -a', 'git branch feature-branch', 'git branch -d feature-branch'],
          ),
          Subcommand(
            name: 'checkout',
            description: 'Switch branches or restore working tree files',
            usage: 'git checkout [options] <branch>',
            examples: ['git checkout main', 'git checkout -b feature-branch', 'git checkout -- file.txt'],
          ),
          Subcommand(
            name: 'merge',
            description: 'Join branches together',
            usage: 'git merge [options] <branch>',
            examples: ['git merge feature-branch', 'git merge --no-ff feature-branch'],
          ),
          Subcommand(
            name: 'rebase',
            description: 'Reapply commits on top of another base',
            usage: 'git rebase [options] [upstream] [branch]',
            examples: ['git rebase main', 'git rebase -i main', 'git rebase --abort'],
          ),
          Subcommand(
            name: 'stash',
            description: 'Stash changes away',
            usage: 'git stash [options]',
            examples: ['git stash', 'git stash pop', 'git stash list', 'git stash clear'],
          ),
        ],
        seeAlso: ['github', 'gitlab', 'bitbucket'],
        references: ['https://git-scm.com/docs'],
        category: 'version-control',
      ),
      
      'docker': CommandDocumentation(
        command: 'docker',
        description: 'Docker container platform',
        usage: 'docker <command> [options]',
        examples: [
          'docker ps',
          'docker run -it ubuntu /bin/bash',
          'docker build -t myapp .',
          'docker push myregistry/myapp:latest',
          'docker exec -it container /bin/bash',
          'docker logs -f container',
          'docker stop container',
          'docker rm container',
          'docker images',
          'docker network ls',
          'docker volume ls',
        ],
        options: [
          CommandOption(
            name: '--help',
            description: 'Show help information',
            type: 'flag',
          ),
          CommandOption(
            name: '--version',
            description: 'Show version information',
            type: 'flag',
          ),
          CommandOption(
            name: '--verbose',
            description: 'Enable verbose output',
            type: 'flag',
            shortName: '-v',
          ),
          CommandOption(
            name: '--detach',
            description: 'Run container in background',
            type: 'flag',
            shortName: '-d',
          ),
          CommandOption(
            name: '--interactive',
            description: 'Keep STDIN open',
            type: 'flag',
            shortName: '-i',
          ),
          CommandOption(
            name: '--tty',
            description: 'Allocate a pseudo-TTY',
            type: 'flag',
            shortName: '-t',
          ),
          CommandOption(
            name: '--publish',
            description: 'Publish a container\'s port(s)',
            type: 'argument',
            argument: '<port>',
          ),
          CommandOption(
            name: '--volume',
            description: 'Bind mount a volume',
            type: 'argument',
            argument: '<host-path>:<container-path>',
          ),
          CommandOption(
            name: '--env',
            description: 'Set environment variables',
            type: 'argument',
            argument: '<key=value>',
          ),
        ],
        subcommands: [
          Subcommand(
            name: 'ps',
            description: 'List containers',
            usage: 'docker ps [options]',
            examples: ['docker ps', 'docker ps -a', 'docker ps -q'],
          ),
          Subcommand(
            name: 'run',
            description: 'Run a command in a new container',
            usage: 'docker run [options] <image> [command]',
            examples: ['docker run -it ubuntu /bin/bash', 'docker run -d nginx', 'docker run --rm alpine ls'],
          ),
          Subcommand(
            name: 'build',
            description: 'Build an image from a Dockerfile',
            usage: 'docker build [options] <path>',
            examples: ['docker build .', 'docker build -t myapp .', 'docker build --no-cache .'],
          ),
          Subcommand(
            name: 'push',
            description: 'Push an image to a registry',
            usage: 'docker push [options] <name>',
            examples: ['docker push myregistry/myapp:latest', 'docker push --all-tags'],
          ),
          Subcommand(
            name: 'pull',
            description: 'Pull an image from a registry',
            usage: 'docker pull [options] <name>',
            examples: ['docker pull ubuntu:latest', 'docker pull node:14-alpine'],
          ),
          Subcommand(
            name: 'exec',
            description: 'Execute a command in a running container',
            usage: 'docker exec [options] <container> <command>',
            examples: ['docker exec -it container /bin/bash', 'docker exec container ls -la'],
          ),
          Subcommand(
            name: 'logs',
            description: 'Fetch the logs of a container',
            usage: 'docker logs [options] <container>',
            examples: ['docker logs -f container', 'docker logs --tail 100 container'],
          ),
          Subcommand(
            name: 'stop',
            description: 'Stop one or more running containers',
            usage: 'docker stop [options] <container>',
            examples: ['docker stop container', 'docker stop -t 5 container'],
          ),
          Subcommand(
            name: 'rm',
            description: 'Remove one or more containers',
            usage: 'docker rm [options] <container>',
            examples: ['docker rm container', 'docker rm -f container'],
          ),
          Subcommand(
            name: 'images',
            description: 'List images',
            usage: 'docker images [options]',
            examples: ['docker images', 'docker images -a', 'docker images --filter "dangling"'],
          ),
          Subcommand(
            name: 'network',
            description: 'Manage networks',
            usage: 'docker network <command> [options]',
            examples: ['docker network ls', 'docker network create mynet', 'docker network connect mynet container'],
          ),
          Subcommand(
            name: 'volume',
            description: 'Manage volumes',
            usage: 'docker volume <command> [options]',
            examples: ['docker volume ls', 'docker volume create myvol', 'docker volume rm myvol'],
          ),
        ],
        seeAlso: ['docker-compose', 'kubernetes', 'podman'],
        references: ['https://docs.docker.com/engine/reference/commandline/cli/'],
        category: 'containerization',
      ),
      
      'npm': CommandDocumentation(
        command: 'npm',
        description: 'Node.js package manager',
        usage: 'npm <command> [package]',
        examples: [
          'npm install',
          'npm install package',
          'npm install --save-dev package',
          'npm run start',
          'npm run build',
          'npm test',
          'npm publish',
          'npm update',
          'npm outdated',
          'npm ls',
          'npm init',
          'npm config set registry https://registry.npmjs.org/',
        ],
        options: [
          CommandOption(
            name: '--help',
            description: 'Show help information',
            type: 'flag',
          ),
          CommandOption(
            name: '--version',
            description: 'Show version information',
            type: 'flag',
          ),
          CommandOption(
            name: '--save',
            description: 'Save package to dependencies',
            type: 'flag',
          ),
          CommandOption(
            name: '--save-dev',
            description: 'Save package to devDependencies',
            type: 'flag',
          ),
          CommandOption(
            name: '--global',
            description: 'Install package globally',
            type: 'flag',
            shortName: '-g',
          ),
          CommandOption(
            name: '--force',
            description: 'Force installation',
            type: 'flag',
            shortName: '-f',
          ),
          CommandOption(
            name: '--production',
            description: 'Ignore devDependencies',
            type: 'flag',
          ),
        ],
        subcommands: [
          Subcommand(
            name: 'install',
            description: 'Install a package',
            usage: 'npm install [package]',
            examples: ['npm install', 'npm install package', 'npm install --save-dev package'],
          ),
          Subcommand(
            name: 'run',
            description: 'Run a script',
            usage: 'npm run <script>',
            examples: ['npm run start', 'npm run build', 'npm run test'],
          ),
          Subcommand(
            name: 'test',
            description: 'Run tests',
            usage: 'npm test [options]',
            examples: ['npm test', 'npm test -- --grep="test name"'],
          ),
          Subcommand(
            name: 'build',
            description: 'Build the package',
            usage: 'npm run build',
            examples: ['npm run build'],
          ),
          Subcommand(
            name: 'publish',
            description: 'Publish the package',
            usage: 'npm publish [options]',
            examples: ['npm publish', 'npm publish --tag beta'],
          ),
          Subcommand(
            name: 'update',
            description: 'Update a package',
            usage: 'npm update [package]',
            examples: ['npm update', 'npm update package'],
          ),
          Subcommand(
            name: 'ls',
            description: 'List installed packages',
            usage: 'npm ls [options]',
            examples: ['npm ls', 'npm ls --depth=0'],
          ),
          Subcommand(
            name: 'outdated',
            description: 'Check for outdated packages',
            usage: 'npm outdated [package]',
            examples: ['npm outdated', 'npm outdated --depth=0'],
          ),
          Subcommand(
            name: 'init',
            description: 'Create a package.json file',
            usage: 'npm init [options]',
            examples: ['npm init', 'npm init -y'],
          ),
          Subcommand(
            name: 'config',
            description: 'Manage npm configuration',
            usage: 'npm config <command> [key] [value]',
            examples: ['npm config list', 'npm config set registry https://registry.npmjs.org/'],
          ),
        ],
        seeAlso: ['yarn', 'pnpm', 'node'],
        references: ['https://docs.npmjs.com/cli-commands'],
        category: 'package-manager',
      ),
      
      'kubectl': CommandDocumentation(
        command: 'kubectl',
        description: 'Kubernetes command line tool',
        usage: 'kubectl [command] [TYPE] [NAME]',
        examples: [
          'kubectl get pods',
          'kubectl get services',
          'kubectl get deployments',
          'kubectl describe pod mypod',
          'kubectl logs mypod',
          'kubectl exec -it mypod /bin/bash',
          'kubectl apply -f deployment.yaml',
          'kubectl delete -f deployment.yaml',
          'kubectl scale deployment myapp --replicas=3',
          'kubectl port-forward service/myservice 8080:80',
          'kubectl top pods',
          'kubectl config use-context mycluster',
        ],
        options: [
          CommandOption(
            name: '--help',
            description: 'Show help information',
            type: 'flag',
          ),
          CommandOption(
            name: '--kubeconfig',
            description: 'Path to kubeconfig file',
            type: 'argument',
            argument: '<file>',
          ),
          CommandOption(
            name: '--namespace',
            description: 'Kubernetes namespace',
            type: 'argument',
            argument: '<namespace>',
            shortName: '-n',
          ),
          CommandOption(
            name: '--context',
            description: 'Kubernetes context',
            type: 'argument',
            argument: '<context>',
          ),
          CommandOption(
            name: '--selector',
            description: 'Label selector',
            type: 'argument',
            argument: '<selector>',
            shortName: '-l',
          ),
          CommandOption(
            name: '--output',
            description: 'Output format',
            type: 'argument',
            argument: '<format>',
            shortName: '-o',
          ),
        ],
        subcommands: [
          Subcommand(
            name: 'get',
            description: 'Display one or many resources',
            usage: 'kubectl get [resource] [name]',
            examples: ['kubectl get pods', 'kubectl get services', 'kubectl get deployments'],
          ),
          Subcommand(
            name: 'describe',
            description: 'Show details of a specific resource',
            usage: 'kubectl describe <resource> <name>',
            examples: ['kubectl describe pod mypod', 'kubectl describe service myservice'],
          ),
          Subcommand(
            name: 'create',
            description: 'Create a resource from a file or stdin',
            usage: 'kubectl create -f <filename>',
            examples: ['kubectl create -f deployment.yaml', 'kubectl create -f -'],
          ),
          Subcommand(
            name: 'apply',
            description: 'Apply a configuration to a resource',
            usage: 'kubectl apply -f <filename>',
            examples: ['kubectl apply -f deployment.yaml', 'kubectl apply -f -'],
          ),
          Subcommand(
            name: 'delete',
            description: 'Delete resources by filenames, stdin, resources and names',
            usage: 'kubectl delete -f <filename>',
            examples: ['kubectl delete -f deployment.yaml', 'kubectl delete service myservice'],
          ),
          Subcommand(
            name: 'edit',
            description: 'Edit a resource on the server',
            usage: 'kubectl edit <resource> <name>',
            examples: ['kubectl edit deployment myapp', 'kubectl edit service myservice'],
          ),
          Subcommand(
            name: 'logs',
            description: 'Print the logs for a container in a pod',
            usage: 'kubectl logs <pod> [-c <container>]',
            examples: ['kubectl logs mypod', 'kubectl logs mypod -c mycontainer', 'kubectl logs -f mypod'],
          ),
          Subcommand(
            name: 'exec',
            description: 'Execute a command in a container',
            usage: 'kubectl exec <pod> [-c <container>] -- <command>',
            examples: ['kubectl exec -it mypod /bin/bash', 'kubectl exec mypod ls -la'],
          ),
          Subcommand(
            name: 'port-forward',
            description: 'Forward one or more local ports to a pod',
            usage: 'kubectl port-forward <pod> [LOCAL_PORT:]REMOTE_PORT',
            examples: ['kubectl port-forward mypod 8080:80', 'kubectl port-forward service/myservice 8080:80'],
          ),
          Subcommand(
            name: 'scale',
            description: 'Set a new size for a deployment, replica set, or replication controller',
            usage: 'kubectl scale deployment <deployment> --replicas=<count>',
            examples: ['kubectl scale deployment myapp --replicas=3', 'kubectl scale rc myrc --replicas=2'],
          ),
          Subcommand(
            name: 'top',
            description: 'Display resource (CPU/memory) usage of nodes or pods',
            usage: 'kubectl top [node | pod]',
            examples: ['kubectl top nodes', 'kubectl top pods', 'kubectl top pod mypod'],
          ),
        ],
        seeAlso: ['helm', 'istio', 'minikube'],
        references: ['https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands'],
        category: 'kubernetes',
      ),
    };
    
    _commandDocs.addAll(builtInCommands);
  }
  
  /// Load system commands
  Future<void> _loadSystemCommands() async {
    try {
      // Load system command documentation from man pages
      final systemCommands = <String, CommandDocumentation>{};
      
      final commonCommands = [
        'ls', 'cd', 'pwd', 'mkdir', 'rm', 'cp', 'mv', 'chmod', 'chown',
        'ps', 'kill', 'top', 'htop', 'df', 'du', 'free', 'uname', 'whoami',
        'grep', 'sed', 'awk', 'sort', 'uniq', 'wc', 'head', 'tail', 'find', 'locate',
        'tar', 'gzip', 'gunzip', 'zip', 'unzip', 'ssh', 'scp', 'rsync',
        'curl', 'wget', 'ping', 'traceroute', 'netstat', 'ss', 'lsof',
        'mount', 'umount', 'fdisk', 'lsblk', 'blkid', 'systemctl',
        'journalctl', 'dmesg', 'lspci', 'lsusb', 'uptime', 'date', 'cal',
      ];
      
      for (final command in commonCommands) {
        final doc = await _getSystemCommandDocumentation(command);
        if (doc != null) {
          systemCommands[command] = doc;
        }
      }
      
      _commandDocs.addAll(systemCommands);
      debugPrint('📚 Loaded ${systemCommands.length} system command documentations');
    } catch (e) {
      debugPrint('⚠️ Failed to load system commands: $e');
    }
  }
  
  /// Get system command documentation
  Future<CommandDocumentation?> _getSystemCommandDocumentation(String command) async {
    try {
      // Try to get man page
      final result = await Process.run('man', [command], runInShell: true);
      if (result.exitCode == 0) {
        final manPage = result.stdout as String;
        return _parseManPage(command, manPage);
      }
      
      // Try to get help output
      final helpResult = await Process.run(command, ['--help'], runInShell: true);
      if (helpResult.exitCode == 0) {
        final helpOutput = helpResult.stdout as String;
        return _parseHelpOutput(command, helpOutput);
      }
      
      return null;
    } catch (e) {
      debugPrint('⚠️ Failed to get documentation for $command: $e');
      return null;
    }
  }
  
  /// Parse man page
  CommandDocumentation _parseManPage(String command, String manPage) {
    final lines = manPage.split('\n');
    String description = '';
    String usage = '';
    final examples = <String>[];
    final options = <CommandOption>[];
    
    bool inSynopsis = false;
    bool inDescription = false;
    
    for (final line in lines) {
      if (line.contains('SYNOPSIS')) {
        inSynopsis = true;
        inDescription = false;
        continue;
      }
      
      if (line.contains('DESCRIPTION')) {
        inSynopsis = false;
        inDescription = true;
        continue;
      }
      
      if (line.contains('OPTIONS')) {
        inSynopsis = false;
        inDescription = false;
        continue;
      }
      
      if (line.contains('EXAMPLES')) {
        inSynopsis = false;
        inDescription = false;
        continue;
      }
      
      if (inSynopsis && line.trim().isNotEmpty) {
        usage += line.trim() + ' ';
      } else if (inDescription && line.trim().isNotEmpty) {
        description += line.trim() + ' ';
      } else if (line.contains('EXAMPLES')) {
        // Extract examples
        final exampleMatch = RegExp(r'\s+([a-zA-Z0-9\s\-_.]+)').firstMatch(line);
        if (exampleMatch != null) {
          examples.add(exampleMatch.group(1)!);
        }
      }
    }
    
    return CommandDocumentation(
      command: command,
      description: description.trim(),
      usage: usage.trim(),
      examples: examples,
      options: options,
      category: 'system',
    );
  }
  
  /// Parse help output
  CommandDocumentation _parseHelpOutput(String command, String helpOutput) {
    final lines = helpOutput.split('\n');
    String description = '';
    String usage = '';
    final examples = <String>[];
    final options = <CommandOption>[];
    
    for (final line in lines) {
      if (line.contains('Usage:') || line.contains('USAGE:')) {
        usage = line.substring(line.indexOf(':') + 1).trim();
      } else if (line.contains('Description:') || line.contains('DESCRIPTION:')) {
        description = line.substring(line.indexOf(':') + 1).trim();
      } else if (line.contains('Example:') || line.contains('EXAMPLE:')) {
        final example = line.substring(line.indexOf(':') + 1).trim();
        examples.add(example);
      }
    }
    
    return CommandDocumentation(
      command: command,
      description: description,
      usage: usage,
      examples: examples,
      options: options,
      category: 'system',
    );
  }
  
  /// Load user commands
  Future<void> _loadUserCommands() async {
    try {
      final userCommandsFile = File('${Platform.environment['HOME']}/.termisol/user_commands.json');
      if (await userCommandsFile.exists()) {
        final content = await userCommandsFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        final commandsData = data['commands'] as Map<String, dynamic>?;
        if (commandsData != null) {
          for (final entry in commandsData.entries) {
            final doc = CommandDocumentation.fromJson(entry.value as Map<String, dynamic>);
            _commandDocs[entry.key] = doc;
          }
        }
      }
      
      debugPrint('📚 Loaded user command documentation');
    } catch (e) {
      debugPrint('⚠️ Failed to load user commands: $e');
    }
  }
  
  /// Setup syntax highlighting
  void _setupSyntaxHighlighting() {
    // Setup syntax highlighting rules for different command types
    _syntaxHighlights.addAll({
      'bash': SyntaxHighlight(
        language: 'bash',
        keywords: [
          'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done',
          'case', 'esac', 'function', 'return', 'break', 'continue',
          'export', 'local', 'readonly', 'declare', 'typeset',
          'echo', 'printf', 'read', 'source', 'alias', 'unalias',
          'cd', 'pwd', 'ls', 'mkdir', 'rm', 'cp', 'mv', 'chmod', 'chown',
          'ps', 'kill', 'jobs', 'bg', 'fg', 'history', 'grep', 'sed', 'awk',
          'tar', 'gzip', 'gunzip', 'ssh', 'scp', 'curl', 'wget',
        ],
        patterns: [
          RegExp(r'\b(if|then|else|elif|fi|for|while|do|done)\b'),
          RegExp(r'\b(function|return|break|continue)\b'),
          RegExp(r'\b(export|local|readonly|declare)\b'),
          RegExp(r'\b(echo|printf|read|source)\b'),
          RegExp(r'\b(cd|pwd|ls|mkdir|rm|cp|mv)\b'),
          RegExp(r'["\'][^"\']*["\']'),
          RegExp(r'["\'][^"\']*["\']'),
          RegExp(r'\$\([^)]*\)'),
          RegExp(r'#.*$'),
        ],
        comments: [
          RegExp(r'#.*$'),
        ],
      ),
      
      'python': SyntaxHighlight(
        language: 'python',
        keywords: [
          'def', 'class', 'if', 'elif', 'else', 'for', 'while', 'do', 'try',
          'except', 'finally', 'with', 'as', 'import', 'from', 'return',
          'yield', 'lambda', 'and', 'or', 'not', 'in', 'is', 'None',
          'True', 'False', 'pass', 'break', 'continue', 'global',
          'assert', 'del', 'raise', 'exec', 'print', 'input',
        ],
        patterns: [
          RegExp(r'\b(def|class|if|elif|else|for|while|try|except|finally|with|as|import|from|return|yield|lambda)\b'),
          RegExp(r'\b(and|or|not|in|is|None|True|False|pass|break|continue)\b'),
          RegExp(r'["\'][^"\']*["\']'),
          RegExp(r'["\'][^"\']*["\']'),
          RegExp(r'\$\([^)]*\)'),
          RegExp(r'#.*$'),
          RegExp(r'""".*"""'),
        ],
        comments: [
          RegExp(r'#.*$'),
          RegExp(r'""".*"""'),
        ],
      ),
      
      'json': SyntaxHighlight(
        language: 'json',
        keywords: ['true', 'false', 'null'],
        patterns: [
          RegExp(r'"[^"\\]*(\\.[^"\\]*)*"'),
          RegExp(r"'[^'\\]*(\\.[^'\\]*)*'"),
          RegExp(r'\b(true|false|null)\b'),
          RegExp(r':\s*'),
          RegExp(r',\s*'),
          RegExp(r'\{\s*'),
          RegExp(r'\}\s*'),
          RegExp(r'\[\s*'),
          RegExp(r'\]\s*'),
        ],
        comments: [],
      ),
    });
  }
  
  /// Get command hints
  List<CommandHint> getCommandHints(String input, {String? workingDirectory}) {
    final hints = <CommandHint>[];
    final words = input.split(' ');
    
    for (final word in words) {
      if (word.isEmpty) continue;
      
      // Check for exact command match
      if (_commandDocs.containsKey(word)) {
        final doc = _commandDocs[word]!;
        hints.add(CommandHint(
          type: HintType.command,
          text: word,
          description: doc.description,
          usage: doc.usage,
          examples: doc.examples.take(3),
        ));
      }
      
      // Check for subcommand match
      for (final entry in _commandDocs.entries) {
        final doc = entry.value;
        for (final subcommand in doc.subcommands) {
          if (subcommand.name.startsWith(word)) {
            hints.add(CommandHint(
              type: HintType.subcommand,
              text: subcommand.name,
              description: subcommand.description,
              usage: subcommand.usage,
              examples: subcommand.examples.take(3),
            ));
          }
        }
      }
      
      // Check for option match
      if (word.startsWith('-')) {
        for (final entry in _commandDocs.entries) {
          final doc = entry.value;
          for (final option in doc.options) {
            if (option.name == word || option.shortName == word) {
              hints.add(CommandHint(
                type: HintType.option,
                text: option.name,
                description: option.description,
                usage: option.argument != null ? '${entry.key} ${option.argument}' : option.name,
              ));
            }
          }
        }
      }
    }
    
    // Sort hints by relevance
    hints.sort((a, b) => _calculateHintScore(b, input).compareTo(_calculateHintScore(a, input)));
    
    return hints.take(_config.maxHints).toList();
  }
  
  /// Calculate hint score
  double _calculateHintScore(CommandHint hint, String input) {
    double score = 0.0;
    
    // Exact match bonus
    if (hint.text.toLowerCase() == input.toLowerCase()) {
      score += 10.0;
    }
    
    // Prefix match bonus
    if (hint.text.toLowerCase().startsWith(input.toLowerCase())) {
      score += 5.0;
    }
    
    // Type priority
    switch (hint.type) {
      case HintType.command:
        score += 3.0;
        break;
      case HintType.subcommand:
        score += 2.0;
        break;
      case HintType.option:
        score += 1.0;
        break;
    }
    
    return score;
  }
  
  /// Get syntax highlighting
  SyntaxHighlight? getSyntaxHighlighting(String language) {
    return _syntaxHighlights[language];
  }
  
  /// Get interactive help
  Future<String> getInteractiveHelp(String command, {String? subcommand}) async {
    final doc = _commandDocs[command];
    if (doc == null) {
      return 'Command not found: $command';
    }
    
    // Build help text
    final helpText = StringBuffer();
    helpText.writeln('Command: ${doc.command}');
    helpText.writeln('Description: ${doc.description}');
    helpText.writeln();
    helpText.writeln('Usage: ${doc.usage}');
    helpText.writeln();
    
    if (subcommand != null) {
      final subcommandDoc = doc.subcommands.firstWhere((sc) => sc.name == subcommand, orElse: () => Subcommand(name: '', description: '', usage: ''));
      helpText.writeln('Subcommand: $subcommand');
      helpText.writeln('Description: ${subcommandDoc.description}');
      helpText.writeln('Usage: ${subcommandDoc.usage}');
      helpText.writeln();
      
      if (subcommandDoc.examples.isNotEmpty) {
        helpText.writeln('Examples:');
        for (final example in subcommandDoc.examples.take(5)) {
          helpText.writeln('  $example');
        }
      }
    } else {
      if (doc.examples.isNotEmpty) {
        helpText.writeln('Examples:');
        for (final example in doc.examples.take(5)) {
          helpText.writeln('  $example');
        }
      }
    }
    
    if (doc.options.isNotEmpty) {
      helpText.writeln();
      helpText.writeln('Options:');
      for (final option in doc.options) {
        final optionText = option.shortName != null 
            ? '${option.name}, ${option.shortName}'
            : option.name;
        helpText.writeln('  $optionText: ${option.description}');
      }
    }
    
    if (doc.references.isNotEmpty) {
      helpText.writeln();
      helpText.writeln('References:');
      for (final reference in doc.references) {
        helpText.writeln('  $reference');
      }
    }
    
    return helpText.toString();
  }
  
  /// Add user command documentation
  void addUserCommand(String command, CommandDocumentation doc) {
    _commandDocs[command] = doc;
    
    // Save to file
    _saveUserCommands();
    
    debugPrint('➕ Added user command documentation: $command');
  }
  
  /// Remove user command documentation
  void removeUserCommand(String command) {
    _commandDocs.remove(command);
    
    // Save to file
    _saveUserCommands();
    
    debugPrint('➖ Removed user command documentation: $command');
  }
  
  /// Save user commands
  Future<void> _saveUserCommands() async {
    try {
      final userCommands = _commandDocs.entries
          .where((entry) => !_isBuiltInCommand(entry.key))
          .map((entry) => MapEntry(entry.key, entry.value.toJson()))
          .toMap();
      
      final data = {
        'commands': userCommands,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      final userCommandsFile = File('${Platform.environment['HOME']}/.termisol/user_commands.json');
      await userCommandsFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save user commands: $e');
    }
  }
  
  /// Check if command is built-in
  bool _isBuiltInCommand(String command) {
    const builtInCommands = {
      'git', 'docker', 'npm', 'kubectl', 'yarn', 'pip', 'python', 'node',
      'java', 'javac', 'gcc', 'make', 'cmake', 'cargo', 'rustc',
      'go', 'run', 'build', 'test', 'install', 'vim', 'nano',
      'emacs', 'code', 'ssh', 'scp', 'rsync', 'curl', 'wget', 'tar',
    };
    
    return builtInCommands.contains(command);
  }
  
  /// Get command statistics
  CommandStatistics getStatistics() {
    return CommandStatistics(
      totalCommands: _commandDocs.length,
      builtinCommands: _commandDocs.keys.where(_isBuiltInCommand).length,
      userCommands: _commandDocs.keys.where((c) => !_isBuiltInCommand(c)).length,
      syntaxHighlights: _syntaxHighlights.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  /// Export command documentation
  String exportDocumentation() {
    final data = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'commands': _commandDocs.map((key, doc) => MapEntry(key, doc.toJson())).toMap(),
      'syntaxHighlights': _syntaxHighlights.map((key, highlight) => MapEntry(key, highlight.toJson())).toMap(),
    };
    
    return jsonEncode(data);
  }
  
  /// Import command documentation
  bool importDocumentation(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      final commandsData = data['commands'] as Map<String, dynamic>?;
      if (commandsData != null) {
        for (final entry in commandsData.entries) {
          _commandDocs[entry.key] = CommandDocumentation.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      
      final syntaxData = data['syntaxHighlights'] as Map<String, dynamic>?;
      if (syntaxData != null) {
        for (final entry in syntaxData.entries) {
          _syntaxHighlights[entry.key] = SyntaxHighlight.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      
      debugPrint('📥 Imported command documentation successfully');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import command documentation: $e');
      return false;
    }
  }
  
  /// Dispose resources
  void dispose() {
    _commandDocs.clear();
    _commandHints.clear();
    _syntaxHighlights.clear();
    _contexts.clear();
    _commandHistory.clear();
    _helpSystem.dispose();
    
    _isInitialized = false;
    debugPrint('💡 Command Hints disposed');
  }
}

/// Command documentation data structure
class CommandDocumentation {
  final String command;
  final String description;
  final String usage;
  final List<String> examples;
  final List<CommandOption> options;
  final List<Subcommand> subcommands;
  final List<String> seeAlso;
  final List<String> references;
  final String category;
  
  CommandDocumentation({
    required this.command,
    required this.description,
    required this.usage,
    required this.examples,
    required this.options,
    required this.subcommands,
    this.seeAlso = const [],
    this.references = const [],
    required this.category,
  });
  
  Map<String, dynamic> toJson() => {
    'command': command,
    'description': description,
    'usage': usage,
    'examples': examples,
    'options': options.map((o) => o.toJson()).toList(),
    'subcommands': subcommands.map((s) => s.toJson()).toList(),
    'seeAlso': seeAlso,
    'references': references,
    'category': category,
  };
  
  factory CommandDocumentation.fromJson(Map<String, dynamic> json) {
    return CommandDocumentation(
      command: json['command'] as String,
      description: json['description'] as String,
      usage: json['usage'] as String,
      examples: List<String>.from(json['examples'] as List? ?? []),
      options: (json['options'] as List<dynamic>?)?.map((o) => CommandOption.fromJson(o as Map<String, dynamic>)).toList() ?? [],
      subcommands: (json['subcommands'] as List<dynamic>?)?.map((s) => Subcommand.fromJson(s as Map<String, dynamic>)).toList() ?? [],
      seeAlso: List<String>.from(json['seeAlso'] as List? ?? []),
      references: List<String>.from(json['references'] as List? ?? []),
      category: json['category'] as String,
    );
  }
}

/// Command option data structure
class CommandOption {
  final String name;
  final String? shortName;
  final String description;
  final String type;
  final String? argument;
  
  CommandOption({
    required this.name,
    this.shortName,
    required this.description,
    required this.type,
    this.argument,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'shortName': shortName,
    'description': description,
    'type': type,
    'argument': argument,
  };
  
  factory CommandOption.fromJson(Map<String, dynamic> json) {
    return CommandOption(
      name: json['name'] as String,
      shortName: json['shortName'] as String?,
      description: json['description'] as String,
      type: json['type'] as String,
      argument: json['argument'] as String?,
    );
  }
}

/// Subcommand data structure
class Subcommand {
  final String name;
  final String description;
  final String usage;
  final List<String> examples;
  
  Subcommand({
    required this.name,
    required this.description,
    required this.usage,
    required this.examples,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'usage': usage,
    'examples': examples,
  };
  
  factory Subcommand.fromJson(Map<String, dynamic> json) {
    return Subcommand(
      name: json['name'] as String,
      description: json['description'] as String,
      usage: json['usage'] as String,
      examples: List<String>.from(json['examples'] as List? ?? []),
    );
  }
}

/// Command hint data structure
class CommandHint {
  final HintType type;
  final String text;
  final String description;
  final String usage;
  final List<String> examples;
  
  CommandHint({
    required this.type,
    required this.text,
    required this.description,
    required this.usage,
    required this.examples,
  });
}

/// Syntax highlight data structure
class SyntaxHighlight {
  final String language;
  final List<String> keywords;
  final List<RegExp> patterns;
  final List<RegExp> comments;
  
  SyntaxHighlight({
    required this.language,
    required this.keywords,
    required this.patterns,
    required this.comments,
  });
  
  Map<String, dynamic> toJson() => {
    'language': language,
    'keywords': keywords,
    'patterns': patterns.map((p) => p.pattern).toList(),
    'comments': comments.map((c) => c.pattern).toList(),
  };
  
  factory SyntaxHighlight.fromJson(Map<String, dynamic> json) {
    return SyntaxHighlight(
      language: json['language'] as String,
      keywords: List<String>.from(json['keywords'] as List? ?? []),
      patterns: (json['patterns'] as List<dynamic>?)?.map((p) => RegExp(p as String)).toList() ?? [],
      comments: (json['comments'] as List<dynamic>?)?.map((c) => RegExp(c as String)).toList() ?? [],
    );
  }
}

/// Command context data structure
class CommandContext {
  final String workingDirectory;
  final String? shell;
  final List<String>? environment;
  final String? gitBranch;
  final bool? inGitRepo;
  
  CommandContext({
    required this.workingDirectory,
    this.shell,
    this.environment,
    this.gitBranch,
    this.inGitRepo,
  });
}

/// Help system
class HelpSystem {
  bool _isInitialized = false;
  final Map<String, String> _helpTopics = {};
  
  HelpSystem();
  
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Initialize help topics
    _helpTopics.addAll({
      'getting-started': 'Getting started with Termisol',
      'navigation': 'Navigation and shortcuts',
      'search': 'Search and filtering',
      'customization': 'Customization and configuration',
      'troubleshooting': 'Troubleshooting and support',
    });
    
    _isInitialized = true;
  }
  
  String getHelpTopic(String topic) {
    return _helpTopics[topic] ?? 'Help topic not found: $topic';
  }
  
  void dispose() {
    _helpTopics.clear();
    _isInitialized = false;
  }
}

/// Hint type enumeration
enum HintType {
  command,
  subcommand,
  option,
}

/// Command hints configuration
class CommandHintsConfig {
  final int maxHints;
  final bool enableSyntaxHighlighting;
  final bool enableInteractiveHelp;
  final Duration cacheTimeout;
  
  CommandHintsConfig({
    this.maxHints = 10,
    this.enableSyntaxHighlighting = true,
    this.enableInteractiveHelp = true,
    this.cacheTimeout = const Duration(minutes: 30),
  });
  
  Map<String, dynamic> toJson() => {
    'maxHints': maxHints,
    'enableSyntaxHighlighting': enableSyntaxHighlighting,
    'enableInteractiveHelp': enableInteractiveHelp,
    'cacheTimeout': cacheTimeout.inMilliseconds,
  };
  
  factory CommandHintsConfig.fromJson(Map<String, dynamic> json) {
    return CommandHintsConfig(
      maxHints: json['maxHints'] as int? ?? 10,
      enableSyntaxHighlighting: json['enableSyntaxHighlighting'] as bool? ?? true,
      enableInteractiveHelp: json['enableInteractiveHelp'] as bool? ?? true,
      cacheTimeout: Duration(milliseconds: json['cacheTimeout'] as int? ?? 1800000),
    );
  }
}

/// Command statistics data structure
class CommandStatistics {
  final int totalCommands;
  final int builtinCommands;
  final int userCommands;
  final int syntaxHighlights;
  final DateTime lastUpdated;
  
  CommandStatistics({
    required this.totalCommands,
    required this.builtinCommands,
    required this.userCommands,
    required this.syntaxHighlights,
    required this.lastUpdated,
  });
}
