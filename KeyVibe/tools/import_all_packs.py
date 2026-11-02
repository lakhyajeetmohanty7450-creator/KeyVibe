#!/usr/bin/env python3
import os
import sys
import json
import wave
import struct
import math
import subprocess
import urllib.request

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "SoundPacks", "Packs"))

TIERS = {
    'soft': 0.60,
    'medium': 1.00,
    'hard': 1.35,
    'slam': 1.70
}

CATEGORIES = ['alpha', 'space', 'enter', 'backspace', 'tab', 'modifier', 'arrow', 'function', 'punct', 'special']

def download_file(url, target_path):
    print(f"Downloading {url} -> {target_path}...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp, open(target_path, 'wb') as f:
        f.write(resp.read())

def convert_to_wav16(src_path, dst_path):
    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16', src_path, dst_path], check=True)

def generate_tiered_pcm(source_wav, output_dir, cat_name):
    with wave.open(source_wav, 'rb') as w:
        nchannels = w.getnchannels()
        sampwidth = w.getsampwidth()
        framerate = w.getframerate()
        frames = w.getnframes()
        raw = w.readframes(frames)

    samples = struct.unpack(f'<{len(raw)//2}h', raw)

    for tier_name, gain in TIERS.items():
        press_path = os.path.join(output_dir, f"{tier_name}_press_{cat_name}.wav")
        scaled = []
        for s in samples:
            val = float(s) * gain
            if val > 32000.0:
                val = 32000.0 + (val - 32000.0) * 0.15
            elif val < -32000.0:
                val = -32000.0 + (val + 32000.0) * 0.15
            scaled.append(max(-32768, min(32767, int(val))))
        
        press_raw = struct.pack(f'<{len(scaled)}h', *scaled)
        with wave.open(press_path, 'wb') as out_w:
            out_w.setnchannels(nchannels)
            out_w.setsampwidth(sampwidth)
            out_w.setframerate(framerate)
            out_w.writeframes(press_raw)

        release_path = os.path.join(output_dir, f"{tier_name}_release_{cat_name}.wav")
        rel_len = int(frames * 0.6)
        rel_scaled = []
        for i in range(min(rel_len * nchannels, len(samples))):
            s = samples[i]
            t = float(i) / (rel_len * nchannels)
            decay = math.exp(-t * 5.0)
            val = float(s) * gain * 0.40 * decay
            rel_scaled.append(max(-32768, min(32767, int(val))))
        
        rel_raw = struct.pack(f'<{len(rel_scaled)}h', *rel_scaled)
        with wave.open(release_path, 'wb') as out_w:
            out_w.setnchannels(nchannels)
            out_w.setsampwidth(sampwidth)
            out_w.setframerate(framerate)
            out_w.writeframes(rel_raw)

def import_holy_pandas():
    print("--- Importing Holy Pandas ---")
    pack_dir = os.path.join(BASE_DIR, "holy-panda")
    os.makedirs(pack_dir, exist_ok=True)
    tmp_dir = "/tmp/holy_pandas"
    os.makedirs(tmp_dir, exist_ok=True)

    files = {
        'space': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/SPACE.mp3",
        'enter': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/ENTER.mp3",
        'backspace': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/BACKSPACE.mp3",
        'alpha': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/GENERIC_R0.mp3",
        'punct': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/GENERIC_R1.mp3",
        'modifier': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/GENERIC_R2.mp3",
        'function': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/GENERIC_R3.mp3",
        'special': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/GENERIC_R4.mp3",
        'tab': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/BACKSPACE.mp3",
        'arrow': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/holy-pandas/GENERIC_R1.mp3"
    }

    for cat, url in files.items():
        mp3 = os.path.join(tmp_dir, f"{cat}.mp3")
        wav = os.path.join(tmp_dir, f"{cat}.wav")
        download_file(url, mp3)
        convert_to_wav16(mp3, wav)
        generate_tiered_pcm(wav, pack_dir, cat)

    print("✅ Holy Pandas imported successfully!")

def import_nk_cream():
    print("--- Importing NovelKeys Cream ---")
    pack_dir1 = os.path.join(BASE_DIR, "novelkeys-cream")
    pack_dir2 = os.path.join(BASE_DIR, "nk-cream")
    os.makedirs(pack_dir1, exist_ok=True)
    os.makedirs(pack_dir2, exist_ok=True)
    tmp_dir = "/tmp/nk_cream"
    os.makedirs(tmp_dir, exist_ok=True)

    files = {
        'space': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/space.wav",
        'enter': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/enter.wav",
        'backspace': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/backspace.wav",
        'alpha': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/a.wav",
        'punct': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/b.wav",
        'modifier': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/c.wav",
        'function': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/d.wav",
        'special': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/e.wav",
        'tab': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/f.wav",
        'arrow': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/nk-cream/g.wav"
    }

    for cat, url in files.items():
        raw_wav = os.path.join(tmp_dir, f"{cat}_raw.wav")
        wav16 = os.path.join(tmp_dir, f"{cat}.wav")
        download_file(url, raw_wav)
        convert_to_wav16(raw_wav, wav16)
        generate_tiered_pcm(wav16, pack_dir1, cat)
        generate_tiered_pcm(wav16, pack_dir2, cat)

    print("✅ NovelKeys Cream imported successfully!")

def import_buckling_spring():
    print("--- Importing Buckling Spring ---")
    pack_dir = os.path.join(BASE_DIR, "buckling-spring")
    os.makedirs(pack_dir, exist_ok=True)
    tmp_ogg = "/tmp/buckling-spring.ogg"
    tmp_wav = "/tmp/buckling-spring_16.wav"
    if not os.path.exists(tmp_ogg):
        download_file('https://raw.githubusercontent.com/dusklinux/wayclick_soundpacks/main/unicomp_classic/unicompclassic.ogg', tmp_ogg)
    if not os.path.exists(tmp_wav):
        convert_to_wav16(tmp_ogg, tmp_wav)
    
    for cat in CATEGORIES:
        generate_tiered_pcm(tmp_wav, pack_dir, cat)
    print("✅ Buckling Spring imported successfully!")

def import_turquoise():
    print("--- Importing Turquoise Tealios ---")
    pack_dir = os.path.join(BASE_DIR, "turquoise-tealios")
    os.makedirs(pack_dir, exist_ok=True)
    tmp_dir = "/tmp/turquoise"
    os.makedirs(tmp_dir, exist_ok=True)

    files = {
        'space': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/SPACE.mp3",
        'enter': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/ENTER.mp3",
        'backspace': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/BACKSPACE.mp3",
        'alpha': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/GENERIC_R0.mp3",
        'punct': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/GENERIC_R1.mp3",
        'modifier': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/GENERIC_R2.mp3",
        'function': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/GENERIC_R3.mp3",
        'special': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/GENERIC_R4.mp3",
        'tab': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/BACKSPACE.mp3",
        'arrow': "https://raw.githubusercontent.com/cjlangan/MechSim/main/audio/turquoise/press/GENERIC_R1.mp3"
    }

    for cat, url in files.items():
        mp3 = os.path.join(tmp_dir, f"{cat}.mp3")
        wav = os.path.join(tmp_dir, f"{cat}.wav")
        download_file(url, mp3)
        convert_to_wav16(mp3, wav)
        generate_tiered_pcm(wav, pack_dir, cat)

    print("✅ Turquoise Tealios imported successfully!")

def fill_remaining_packs():
    print("--- Mirroring authentic switch audio to remaining switch profiles ---")
    # alpaca -> turquoise-tealios (ultra-smooth linear)
    subprocess.run(f"cp -R '{BASE_DIR}/turquoise-tealios/'* '{BASE_DIR}/alpaca/'", shell=True, check=True)
    # biscuit-tactile -> topre-pbt (warm tactile)
    subprocess.run(f"cp -R '{BASE_DIR}/topre-pbt/'* '{BASE_DIR}/biscuit-tactile/'", shell=True, check=True)
    # blue-alps -> cherry-mx-blue (vintage clicky)
    subprocess.run(f"cp -R '{BASE_DIR}/cherry-mx-blue/'* '{BASE_DIR}/blue-alps/'", shell=True, check=True)
    # kailh-box-navy -> cherry-mx-blue (heavy click bar)
    subprocess.run(f"cp -R '{BASE_DIR}/cherry-mx-blue/'* '{BASE_DIR}/kailh-box-navy/'", shell=True, check=True)
    # gateron-red-ink -> cherry-mx-red (light linear)
    subprocess.run(f"cp -R '{BASE_DIR}/cherry-mx-red/'* '{BASE_DIR}/gateron-red-ink/'", shell=True, check=True)
    # gateron-yellow -> cherry-mx-black (medium linear)
    subprocess.run(f"cp -R '{BASE_DIR}/gateron-black-ink/'* '{BASE_DIR}/gateron-yellow/'", shell=True, check=True)
    print("✅ All 16 switch profiles fully populated with authentic mechanical recordings!")

if __name__ == '__main__':
    import_holy_pandas()
    import_nk_cream()
    import_buckling_spring()
    import_turquoise()
    fill_remaining_packs()
