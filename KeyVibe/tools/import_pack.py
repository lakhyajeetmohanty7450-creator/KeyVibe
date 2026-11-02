#!/usr/bin/env python3
import os
import sys
import json
import wave
import struct
import math
import subprocess
import urllib.request

CATEGORIES = {
    'alpha': ['30', '31', '32', '33', '34', '35', '16', '17', '18', '19', '20'], # A, S, D... Q, W, E...
    'space': ['57'], # Spacebar
    'enter': ['28'], # Enter
    'backspace': ['14'], # Backspace
    'tab': ['15'], # Tab
    'modifier': ['42', '54', '29', '56'], # Shift, Ctrl, Alt
    'arrow': ['103', '108', '105', '106'], # Up, Down, Left, Right
    'function': ['59', '60', '61', '62'], # F1, F2...
    'punct': ['51', '52', '53', '12', '13'], # Comma, Dot, Slash...
    'special': ['1'] # Esc
}

TIERS = {
    'soft': 0.60,
    'medium': 1.00,
    'hard': 1.35,
    'slam': 1.70
}

def download_file(url, target_path):
    print(f"Downloading {url} -> {target_path}...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp, open(target_path, 'wb') as f:
        f.write(resp.read())

def convert_to_wav16(src_path, dst_path):
    print(f"Converting {src_path} -> {dst_path} via afconvert...")
    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16', src_path, dst_path], check=True)

def process_sprite_pack(pack_id, ogg_url, config_url, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    tmp_ogg = f"/tmp/{pack_id}.ogg"
    tmp_json = f"/tmp/{pack_id}.json"
    tmp_wav = f"/tmp/{pack_id}_16.wav"

    if not os.path.exists(tmp_ogg):
        download_file(ogg_url, tmp_ogg)
    if not os.path.exists(tmp_json):
        download_file(config_url, tmp_json)

    if not os.path.exists(tmp_wav):
        convert_to_wav16(tmp_ogg, tmp_wav)

    with open(tmp_json) as f:
        config = json.load(f)

    defines = config.get('defines', {})
    
    with wave.open(tmp_wav, 'rb') as w:
        nchannels = w.getnchannels()
        sampwidth = w.getsampwidth()
        framerate = w.getframerate()
        total_frames = w.getnframes()
        all_raw = w.readframes(total_frames)

    samples = struct.unpack(f'<{len(all_raw)//2}h', all_raw)

    for cat_name, key_codes in CATEGORIES.items():
        found_def = None
        for code in key_codes:
            if code in defines:
                found_def = defines[code]
                break
        if not found_def:
            found_def = defines.get('30') or list(defines.values())[0]

        start_ms, dur_ms = found_def[0], found_def[1]
        start_frame = int((start_ms / 1000.0) * framerate)
        num_frames = int((dur_ms / 1000.0) * framerate)

        # Extract frames
        start_idx = start_frame * nchannels
        end_idx = min(len(samples), (start_frame + num_frames) * nchannels)
        cat_samples = list(samples[start_idx:end_idx])

        # Generate each force tier for press
        for tier_name, gain in TIERS.items():
            press_file = os.path.join(output_dir, f"{tier_name}_press_{cat_name}.wav")
            scaled = []
            for s in cat_samples:
                val = float(s) * gain
                # Soft saturation / limiting
                if val > 32000.0:
                    val = 32000.0 + (val - 32000.0) * 0.15
                elif val < -32000.0:
                    val = -32000.0 + (val + 32000.0) * 0.15
                scaled.append(max(-32768, min(32767, int(val))))

            raw_out = struct.pack(f'<{len(scaled)}h', *scaled)
            with wave.open(press_file, 'wb') as out_w:
                out_w.setnchannels(nchannels)
                out_w.setsampwidth(sampwidth)
                out_w.setframerate(framerate)
                out_w.writeframes(raw_out)

            # Generate release sound (shorter, lighter release clack)
            release_file = os.path.join(output_dir, f"{tier_name}_release_{cat_name}.wav")
            rel_len = int(num_frames * 0.65)
            rel_scaled = []
            for i in range(min(rel_len * nchannels, len(cat_samples))):
                s = cat_samples[i]
                t = float(i) / (rel_len * nchannels)
                decay = math.exp(-t * 4.0)
                val = float(s) * gain * 0.45 * decay
                rel_scaled.append(max(-32768, min(32767, int(val))))

            rel_raw_out = struct.pack(f'<{len(rel_scaled)}h', *rel_scaled)
            with wave.open(release_file, 'wb') as out_w:
                out_w.setnchannels(nchannels)
                out_w.setsampwidth(sampwidth)
                out_w.setframerate(framerate)
                out_w.writeframes(rel_raw_out)

    print(f"✅ Generated all 80 force-tiered PCM samples for pack '{pack_id}' in {output_dir}")

if __name__ == '__main__':
    pack = sys.argv[1]
    ogg_url = sys.argv[2]
    json_url = sys.argv[3]
    out_dir = sys.argv[4]
    process_sprite_pack(pack, ogg_url, json_url, out_dir)

