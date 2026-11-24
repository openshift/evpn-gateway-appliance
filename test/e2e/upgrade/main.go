package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	peerGroup = "evpn_upgrade_peers"
	journal   = "journalctl --directory=/var/log/journal --no-pager"
	badMarker = "EGA_E2E_BAD_CANDIDATE"
)

var (
	digestPattern = regexp.MustCompile(`^sha256:[0-9a-f]{64}$`)
	hostPattern   = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.-]*$`)
)

type imageSlot struct {
	Image struct {
		Digest string                     `json:"imageDigest"`
		Source struct{ Transport string } `json:"image"`
	} `json:"image"`
}

type bootcStatus struct {
	Status struct {
		Booted         imageSlot  `json:"booted"`
		Rollback       imageSlot  `json:"rollback"`
		Staged         *imageSlot `json:"staged"`
		RollbackQueued bool       `json:"rollbackQueued"`
	} `json:"status"`
}

type boot struct {
	ID string `json:"boot_id"`
}

type snapshot struct {
	bootID    string
	digest    string
	transport string
	rollback  string
	history   []boot
}

func (s snapshot) since(previous snapshot, count int) ([]boot, error) {
	for i, b := range s.history {
		if b.ID == previous.bootID && len(s.history)-i-1 == count {
			return s.history[i:], nil
		}
	}
	return nil, fmt.Errorf("expected %d boots after %s, current boot is %s", count, previous.bootID, s.bootID)
}

type lab struct {
	inventory string
	hosts     []string
}

func (l lab) command(program, callback string, args ...string) *exec.Cmd {
	cmd := exec.Command(program, append([]string{"-i", l.inventory}, args...)...)
	cmd.Dir = "ansible"
	cmd.Env = append(os.Environ(), "ANSIBLE_NOCOLOR=1", "ANSIBLE_LOAD_CALLBACK_PLUGINS=1", "ANSIBLE_STDOUT_CALLBACK="+callback)
	return cmd
}

func (l lab) probe(target, command string) (map[string]string, error) {
	cmd := l.command("ansible", "ansible.posix.json", target, "--become",
		"--module-name", "ansible.builtin.command", "--args", command)
	output, err := cmd.Output()
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("%s on %s: %w\n%s\n%s", command, target, err, output, exit.Stderr)
		}
		return nil, fmt.Errorf("%s on %s: %w\n%s", command, target, err, output)
	}
	var result struct {
		Plays []struct {
			Tasks []struct {
				Hosts map[string]struct{ Stdout string }
			}
		}
	}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("decode %s output on %s: %w", command, target, err)
	}
	if len(result.Plays) != 1 || len(result.Plays[0].Tasks) != 1 {
		return nil, fmt.Errorf("missing %s result on %s", command, target)
	}
	results := result.Plays[0].Tasks[0].Hosts
	values := make(map[string]string)
	for _, host := range l.hosts {
		if target != peerGroup && target != host {
			continue
		}
		result, found := results[host]
		if !found {
			return nil, fmt.Errorf("missing %s output on %s", command, host)
		}
		values[host] = strings.TrimSpace(result.Stdout)
	}
	return values, nil
}

func (l lab) observe() (map[string]snapshot, error) {
	statuses, err := l.probe(peerGroup, "bootc status --json")
	if err != nil {
		return nil, err
	}
	bootIDs, err := l.probe(peerGroup, "cat /proc/sys/kernel/random/boot_id")
	if err != nil {
		return nil, err
	}
	histories, err := l.probe(peerGroup, journal+" --list-boots --output=json")
	if err != nil {
		return nil, err
	}
	states := make(map[string]snapshot)
	for _, host := range l.hosts {
		var state bootcStatus
		if err := json.Unmarshal([]byte(statuses[host]), &state); err != nil {
			return nil, fmt.Errorf("decode bootc status on %s: %w", host, err)
		}
		var history []boot
		if err := json.Unmarshal([]byte(histories[host]), &history); err != nil {
			return nil, fmt.Errorf("decode boot history on %s: %w", host, err)
		}
		id := strings.ReplaceAll(bootIDs[host], "-", "")
		if id == "" || len(history) == 0 || history[len(history)-1].ID != id {
			return nil, fmt.Errorf("%s does not have a persistent journal for current boot %s", host, id)
		}
		digest := state.Status.Booted.Image.Digest
		if !digestPattern.MatchString(digest) || state.Status.Staged != nil || state.Status.RollbackQueued {
			return nil, fmt.Errorf("%s must be booted from an image without a pending deployment: %s", host, statuses[host])
		}
		rollback := state.Status.Rollback.Image.Digest
		states[host] = snapshot{bootID: id, digest: digest, transport: state.Status.Booted.Image.Source.Transport, rollback: rollback, history: history}
		fmt.Printf("%s boot=%s booted=%s rollback=%s\n", host, id, digest, rollback)
	}
	return states, nil
}

func (l lab) play(callback string, args ...string) (string, error) {
	cmd := l.command("ansible-playbook", callback, args...)
	var output bytes.Buffer
	writer := io.MultiWriter(os.Stdout, &output)
	cmd.Stdout, cmd.Stderr = writer, os.Stderr
	if callback == "default" {
		cmd.Stderr = writer
	}
	err := cmd.Run()
	return output.String(), err
}

func (l lab) upgrade(image, layout, callback string) (string, error) {
	vars, err := json.Marshal(map[string]string{"evpn_upgrade_image": image, "evpn_upgrade_oci_dir": layout, "evpn_upgrade_source": "local"})
	if err != nil {
		return "", err
	}
	return l.play(callback, "playbooks/upgrade.yml", "--extra-vars", string(vars))
}

func (l lab) checkHealth(phase string) error {
	if _, err := l.play("default", "playbooks/health-check.yml", "--limit", peerGroup); err != nil {
		return fmt.Errorf("peer health check after %s failed: %w", phase, err)
	}
	return nil
}

func verifySerialHealth(output, first, second string) error {
	var report struct {
		Plays []struct {
			Tasks []struct {
				Task struct {
					Name, Path string
					Duration   struct{ Start, End time.Time }
				}
				Hosts map[string]struct {
					Rebooted, Skipped, Failed bool
					Cmd                       json.RawMessage
				}
			}
		}
	}
	if err := json.Unmarshal([]byte(output), &report); err != nil {
		return fmt.Errorf("read upgrade task events: %w", err)
	}
	var reboot, healthy, handoff, handoffBGP, firstStage, stage time.Time
	copies := make(map[string]time.Time)
	var postBootBGP bool
	for _, play := range report.Plays {
		for _, event := range play.Tasks {
			interval := event.Task.Duration
			if event.Task.Name == "Require the copied release before any peer may stage an upgrade" {
				for host, result := range event.Hosts {
					if !result.Skipped && !result.Failed {
						copies[host] = interval.End
					}
				}
			}
			if r, ok := event.Hosts[first]; ok && !r.Skipped && !r.Failed {
				if !reboot.IsZero() && event.Task.Name == "Recheck fabric health on the peers that will keep serving" {
					handoff = interval.Start
				}
				if r.Rebooted {
					reboot = interval.End
				}
				if !reboot.IsZero() && !interval.Start.Before(reboot) && strings.Contains(event.Task.Path, "/roles/evpn_health_check/tasks/") {
					if handoff.IsZero() {
						healthy = interval.End
						postBootBGP = postBootBGP || strings.Contains(event.Task.Name, "BGP session")
					} else if strings.Contains(event.Task.Name, "BGP session") {
						handoffBGP = interval.End
					}
				}
			}
			for host, result := range event.Hosts {
				var argv []string
				if json.Unmarshal(result.Cmd, &argv) == nil && len(argv) >= 2 && argv[0] == "bootc" && argv[1] == "switch" {
					if host == first {
						firstStage = interval.Start
					} else if host == second {
						stage = interval.Start
					}
				}
			}
		}
	}
	for _, host := range []string{first, second} {
		if copies[host].IsZero() || !copies[host].Before(firstStage) {
			return fmt.Errorf("%s did not verify its local release before %s started staging", host, first)
		}
	}
	if !postBootBGP || !healthy.Before(handoff) || handoffBGP.IsZero() || !handoffBGP.Before(stage) {
		return fmt.Errorf("%s did not pass both post-boot and handoff BGP checks before %s staged its image", first, second)
	}
	return nil
}

func imageDigest(reference string) (string, error) {
	name, digest, _ := strings.Cut(reference, "@")
	if !strings.Contains(name, "/") || !digestPattern.MatchString(digest) {
		return "", fmt.Errorf("expected a fully qualified registry image by sha256 digest: %q", reference)
	}
	return digest, nil
}

func run(inventory, good, bad, goodDir, badDir string) error {
	if !filepath.IsAbs(goodDir) || !filepath.IsAbs(badDir) {
		return fmt.Errorf("supply absolute controller paths for both OCI layouts")
	}
	goodDigest, err := imageDigest(good)
	if err != nil {
		return err
	}
	badDigest, err := imageDigest(bad)
	if err != nil {
		return err
	}
	if goodDigest == badDigest {
		return fmt.Errorf("the healthy and unhealthy candidates must have different digests")
	}
	path, err := filepath.Abs(inventory)
	if err != nil {
		return err
	}
	if _, err := os.Stat(path); err != nil {
		return err
	}
	l := lab{inventory: path}
	output, err := l.command("ansible", "default", peerGroup, "--list-hosts").CombinedOutput()
	_, hosts, found := strings.Cut(string(output), "hosts (2):\n")
	l.hosts = strings.Fields(hosts)
	if err != nil || !found || len(l.hosts) != 2 || !hostPattern.MatchString(l.hosts[0]) || !hostPattern.MatchString(l.hosts[1]) {
		return fmt.Errorf("expected exactly two inventory hosts in %s, got:\n%s", peerGroup, output)
	}
	sort.Strings(l.hosts)
	first, second := l.hosts[0], l.hosts[1]
	before, err := l.observe()
	if err != nil {
		return err
	}
	for _, host := range l.hosts {
		if before[host].digest == goodDigest || before[host].digest == badDigest {
			return fmt.Errorf("%s must start on a digest different from both candidates", host)
		}
	}
	events, err := l.upgrade(good, goodDir, "ansible.posix.json")
	if err != nil {
		return fmt.Errorf("healthy upgrade failed: %w", err)
	}
	if err := verifySerialHealth(events, first, second); err != nil {
		return err
	}
	after, err := l.observe()
	if err != nil {
		return err
	}
	for _, host := range l.hosts {
		if after[host].digest != goodDigest || after[host].transport != "oci" {
			return fmt.Errorf("%s booted %s from %s instead of the verified local release %s", host, after[host].digest, after[host].transport, goodDigest)
		}
		if _, err := after[host].since(before[host], 1); err != nil {
			return fmt.Errorf("healthy upgrade on %s: %w", host, err)
		}
	}
	if err := l.checkHealth("the healthy upgrade"); err != nil {
		return err
	}
	fmt.Printf("PASS: %s and %s booted %s in order\n", first, second, goodDigest)

	failedUpgrade, err := l.upgrade(bad, badDir, "default")
	confirmation := fmt.Sprintf("Post-upgrade health check failed on %s. Rollback verified on %s: %s", first, first, goodDigest)
	if err == nil || !strings.Contains(failedUpgrade, confirmation) {
		return fmt.Errorf("expected failed upgrade with %q, command error: %v", confirmation, err)
	}
	recovered, err := l.observe()
	if err != nil {
		return err
	}
	if recovered[first].digest != goodDigest || recovered[first].rollback != badDigest || recovered[first].transport != "oci" {
		return fmt.Errorf("expected %s to boot %s and retain %s in its rollback slot", first, goodDigest, badDigest)
	}
	history, err := recovered[first].since(after[first], 2)
	if err != nil {
		return fmt.Errorf("failed upgrade on %s: %w", first, err)
	}
	badBoot := history[1].ID
	logs, err := l.probe(first, journal+" --boot="+badBoot+" --unit=frr-container.service --output=cat")
	if err != nil {
		return err
	}
	if !strings.Contains(logs[first], badMarker) {
		return fmt.Errorf("%s boot %s lacks the broken FRR image marker %q", first, badBoot, badMarker)
	}
	if recovered[second].bootID != after[second].bootID || recovered[second].digest != after[second].digest || recovered[second].rollback != after[second].rollback {
		return fmt.Errorf("%s changed boot ID or deployment during the failed upgrade", second)
	}
	if err := l.checkHealth("rollback"); err != nil {
		return err
	}
	fmt.Printf("PASS: %s booted the unhealthy candidate (%s) and recovered; %s stayed on its prior boot\n", first, badBoot, second)
	return nil
}

func main() {
	inventory := flag.String("inventory", "", "existing Ansible inventory for two disposable bootc peers")
	good := flag.String("good", "", "healthy candidate image reference by digest")
	bad := flag.String("bad", "", "FRR-failing candidate image reference by digest")
	goodDir := flag.String("good-oci", "", "absolute controller path to the healthy OCI layout")
	badDir := flag.String("bad-oci", "", "absolute controller path to the FRR-failing OCI layout")
	flag.Parse()
	if *inventory == "" || *good == "" || *bad == "" || *goodDir == "" || *badDir == "" || flag.NArg() != 0 {
		flag.Usage()
		os.Exit(2)
	}
	if err := run(*inventory, *good, *bad, *goodDir, *badDir); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
