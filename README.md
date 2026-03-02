# nds-access-point
Access point for legacy consoles like the NDS and NDSi to connect to the internet.

## Usage
Make sure to copy the dnsmasq and hostapd configuration files to ```/etc/dnsmasq.d/ds-hotspot.conf``` and ```/etc/hostapd/hostapd.conf``` respectively, or use the setup script to copy them for you:
```bash
sudo ./setup.sh
```
After the setup script copies the configuration files, you can run the script by using:
```bash
sudo ./ds-hotspot.sh start
```

And to stop the script:
```bash
sudo ./ds-hotspot.sh stop
```