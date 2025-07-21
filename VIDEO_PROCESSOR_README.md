# Video Processing Pipeline with Ollama

This Python script processes videos through Ollama using a two-stage observation generation process, similar to the Swift implementation in the Dayflow app.

## Features

- **Frame Extraction**: Extracts frames from videos every 60 seconds using ffmpeg
- **Two-Stage Processing**:
  - Stage 1: Analyzes each frame individually to get simple descriptions
  - Stage 2: Merges frame descriptions into 2-5 coherent observations
- **Activity Cards**: Generates activity cards from observations (currently a stub)
- **Comprehensive Logging**: Saves all intermediate outputs and LLM calls for debugging
- **Robust Error Handling**: Continues processing even if individual videos fail

## Requirements

### System Dependencies
- Python 3.8+
- ffmpeg and ffprobe (for video processing)
- Ollama running locally with the `qwen2.5vl:3b` model

### Python Dependencies
```bash
pip install requests pillow
```

### Installing Ollama Model
```bash
ollama pull qwen2.5vl:3b
```

## Usage

### Basic Usage
```bash
python process_videos.py video_list.txt
```

### With Custom Ollama Endpoint
```bash
python process_videos.py video_list.txt --ollama-endpoint http://localhost:11434
```

### With Debug Logging
```bash
python process_videos.py video_list.txt --debug
```

### Video List Format
Create a text file with one video path per line:
```
/path/to/video1.mp4
/path/to/video2.mov
/Users/username/Desktop/recording.mp4
```

## Output Structure

For each processed video, the script creates a debug directory with:

```
debug_output/
├── video_name/
│   ├── frames/                  # Extracted frame images
│   │   ├── frame_0000.jpg
│   │   ├── frame_0001.jpg
│   │   └── ...
│   ├── frame_descriptions/      # Individual frame analysis
│   │   ├── frame_0000_desc.txt
│   │   ├── frame_0001_desc.txt
│   │   └── ...
│   ├── frame_descriptions.json  # All frame descriptions
│   ├── observations.json        # Merged observations
│   ├── activity_cards.json      # Generated activity cards
│   └── llm_calls.json          # All LLM API calls with timing
```

## Data Formats

### Frame Descriptions
```json
[
  {
    "timestamp": 0.0,
    "description": "Writing a project status email in Gmail with spreadsheet attachment open in preview"
  },
  {
    "timestamp": 60.0,
    "description": "Coding a React component in VS Code with terminal showing npm errors at bottom"
  }
]
```

### Observations
```json
[
  {
    "start_ts": 1703001600,
    "end_ts": 1703001960,
    "observation": "Drafted and sent client proposal email in Gmail, referencing budget spreadsheet",
    "metadata": {"model": "qwen2.5vl:3b"}
  }
]
```

### LLM Calls
```json
[
  {
    "timestamp": "2024-01-15T10:30:45.123456",
    "latency": 2.345,
    "model": "qwen2.5vl:3b",
    "input": "Frame analysis at 00:00",
    "output": "Writing documentation in VS Code",
    "error": null
  }
]
```

## Error Handling

- **Missing Videos**: Logs error and continues with next video
- **Frame Extraction Failures**: Logs warning and continues with available frames
- **LLM API Errors**: Falls back to error descriptions, continues processing
- **JSON Parsing Issues**: Attempts multiple parsing strategies before failing

## Performance Considerations

- Frame extraction is the slowest part (depends on video length)
- Each frame analysis takes 2-5 seconds with Ollama
- Total processing time ≈ (video_duration / 60) * 3 seconds + overhead
- For a 30-minute video: expect ~2-3 minutes processing time

## Logging

- Console output: INFO level by default
- Log file: `video_processing.log` with full details
- Use `--debug` flag for verbose logging

## Extending the Script

### Implementing Activity Cards
The `_generate_activity_cards` method is currently a stub. To implement:

1. Add proper prompt for activity categorization
2. Implement user taxonomy support
3. Add distraction detection logic

### Changing Frame Interval
Modify the `FRAME_EXTRACTION_INTERVAL` constant (default: 60 seconds)

### Using Different Models
Pass `--model` parameter or modify `OLLAMA_MODEL` constant

## Troubleshooting

### "Failed to connect to Ollama"
- Ensure Ollama is running: `ollama serve`
- Check the endpoint URL
- Verify the model is installed: `ollama list`

### "ffprobe failed"
- Install ffmpeg: `brew install ffmpeg` (macOS) or `apt install ffmpeg` (Ubuntu)
- Ensure video file path is correct

### "Failed to extract frame"
- Check video file integrity
- Some video formats may not be supported
- Try converting to MP4 first

### Memory Issues
- Large videos may consume significant memory
- Consider processing videos in batches
- Reduce frame quality or extraction frequency