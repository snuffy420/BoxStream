# Box://Stream Helper (optional)

Box://Stream plays everything on your Roku directly, except audio the Roku can't decode:

- **DTS and Dolby TrueHD**: converted to Dolby Digital 5.1 (640 kb/s).
- **Hi-res FLAC above 48 kHz**: converted to 48 kHz / 24-bit.

The helper is your own small server that does only that conversion. Video never goes
through it, and it never converts anything your Roku can already play. It runs on
Oracle Cloud's **Always Free** tier, so it costs nothing.

## Set it up (about 15 minutes, mostly waiting)

1. **Make a free Oracle Cloud account** at <https://signup.cloud.oracle.com>.
   - Oracle asks for a card to verify you, but Always Free servers are never charged.
   - Pick a home region near you. It can't be changed later.
2. **Sign in to the Oracle Cloud console** and open **Cloud Shell**, the `>_` icon at the top right.
3. **Run the setup.** In Cloud Shell, upload `boxstream-setup.sh` (gear menu > Upload), then run:
   ```bash
   bash boxstream-setup.sh
   ```
   It creates the server and its network (HTTPS only), installs the helper, waits until
   the helper answers, and prints:
   ```
   Address:       https://<numbers>.sslip.io
   Pairing code:  XXXXXXXX
   Server name:   cedar-4821
   ```
4. **On your Roku:** go to **Box://Stream > Settings > Helper**, enter the address and the
   pairing code, then press **Test**.

Run `bash boxstream-setup.sh` again any time to see the address and code.

### Removing the server

The setup gives your server a plain random name, such as `cedar-4821`, and prints it with
the address and code. **Keep that name.** To delete the server and its network, run:

```bash
bash boxstream-setup.sh --remove cedar-4821
```

using your server's name. If you've forgotten it, it's listed in the Oracle console under
**Compute > Instances**. In the same Cloud Shell that made the server, `--remove` on its own also
works, because the script remembers the name there.

## Good to know

- **Free limit:** Always Free allows two `VM.Standard.E2.1.Micro` servers per account. The
  helper uses one.
- **"Out of capacity":** Oracle sometimes has no free servers left in a region. Run the
  script again later; capacity usually comes back within hours.
- **Idle reclaim:** Oracle may reclaim Always Free servers that sit idle for a week.
  Upgrading the account to **Pay As You Go** stops that, and Always Free resources stay free.
- **Privacy:** only the pairing code opens the helper. Your seedbox login is sent per
  request, kept in memory for that conversion only, and never written to disk or logs.

## Already have an Ubuntu server?

Copy `boxstream_helper.py` and `install.sh` to the server and run `sudo bash install.sh`.
The server's firewall must allow TCP 80 and 443. On Windows, `setup_helper.pyw` does this
over SSH for you.
