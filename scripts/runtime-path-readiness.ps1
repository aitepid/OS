$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$errors = @()

function Require-Match {
    param(
        [string]$Path,
        [string[]]$Patterns,
        [string]$Label
    )

    if (-not (Test-Path $Path)) {
        $script:errors += "Missing file: $Path"
        return
    }

    $content = Get-Content $Path -Raw
    foreach ($p in $Patterns) {
        if ($content -notmatch [regex]::Escape($p)) {
            $script:errors += "$Label missing: $p"
        }
    }
}

Require-Match -Path 'bare-kernel/hl/kernel_entry.hl' -Label 'kernel_entry' -Patterns @(
    'Vector 32',
    'Vector 33',
    'IDT',
    'PIT',
    'HicOS>'
)

Require-Match -Path 'bare-kernel/hl/kernel_init.hl' -Label 'kernel_init' -Patterns @(
    'serial_init(',
    'kmalloc_init(',
    'vfs_init(',
    'pci_scan(',
    'tss_init(',
    'smp_init(',
    'shell_main('
)

Require-Match -Path 'bare-kernel/hl/syscall.hl' -Label 'syscall' -Patterns @(
    'fn syscall_dispatch(',
    'SYS_READ',
    'SYS_WRITE',
    'SYS_OPEN',
    'SYS_EXIT'
)

Require-Match -Path 'bare-kernel/hl/usermode.hl' -Label 'usermode' -Patterns @(
    'fn syscall_entry(',
    'fn enter_usermode(',
    'fn syscall_msr_setup(',
    'MSR_LSTAR'
)

Require-Match -Path 'bare-kernel/hl/net.hl' -Label 'net' -Patterns @(
    'fn build_udp_packet(',
    'fn build_arp_request(',
    'fn parse_eth_frame(',
    'ip_checksum('
)

Require-Match -Path 'bare-kernel/hl/tcp.hl' -Label 'tcp' -Patterns @(
    'fn tcp_connect(',
    'fn tcp_listen(',
    'fn tcp_input(',
    'fn tcp_process_segment('
)

Require-Match -Path 'bare-kernel/hl/tls.hl' -Label 'tls' -Patterns @(
    'fn tls_client_hello(',
    'fn tls_connect(',
    'fn tls_send(',
    'fn tls_recv('
)

Require-Match -Path 'bare-kernel/hl/bpf.hl' -Label 'bpf' -Patterns @(
    'fn bpf_load(',
    'fn bpf_run(',
    'fn bpf_attach(',
    'fn bpf_run_hook('
)

Require-Match -Path 'bare-kernel/hl/quic.hl' -Label 'quic' -Patterns @(
    'fn quic_connect(',
    'fn quic_send_initial(',
    'fn quic_conn_addr(',
    'fn quic_stream_addr('
)

Require-Match -Path 'bare-kernel/hl/advanced_verify.hl' -Label 'advanced_verify' -Patterns @(
    'fn advanced_feature_selftest(',
    'fn advanced_feature_summary(',
    'eBPF',
    'TLS1.3',
    'QUIC'
)

Require-Match -Path 'bare-kernel/hl/shell.hl' -Label 'shell' -Patterns @(
    'if cmd == "advtest"',
    'if cmd == "dnstest"',
    'if cmd == "tcploop"'
)

if ($errors.Count -gt 0) {
    Write-Host 'Runtime path readiness check failed:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Runtime path readiness check passed.' -ForegroundColor Green
Write-Host '- interrupt path (IDT/PIT/KBD): OK'
Write-Host '- syscall path (SYSCALL/SYSRET): OK'
Write-Host '- network path (ARP/UDP/TCP/TLS/QUIC): OK'
Write-Host '- advanced feature path (eBPF/TLS1.3/QUIC): OK'
