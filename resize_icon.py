from PIL import Image

def resize_icon(input_path, output_path, size=512):
    try:
        img = Image.open(input_path).convert("RGBA")
        
        # Calculate aspect ratio
        w, h = img.size
        ratio = min(size/w, size/h)
        new_w = int(w * ratio)
        new_h = int(h * ratio)
        
        img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        
        # Create new 512x512 transparent image
        new_img = Image.new("RGBA", (size, size), (255, 255, 255, 0)) # transparent
        
        # Paste resized logo into center
        new_img.paste(img, ((size - new_w)//2, (size - new_h)//2))
        
        new_img.save(output_path, "PNG")
        print("Icon successfully resized to 512x512!")
    except Exception as e:
        print(f"Error resizing image: {e}")

input_path = r"D:\logo.png"
output_path = r"C:\Users\user\.gemini\antigravity\brain\38b0efe7-1a23-497a-9b43-d1dfb2199cc6\app_icon_512.png"

resize_icon(input_path, output_path)
