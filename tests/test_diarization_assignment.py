"""
Speaker assignment regression tests.

Focuses on probabilistic speaker labeling in core.transcriber._assign_speakers
without loading ASR or diarization models.
"""

from core.transcriber import _assign_speakers


def test_assign_speakers_preserves_turn_taking_dialogue_pattern():
    whisper_segments = [
        {"start": 0.0, "end": 2.1, "text": "Hey, are you available to work on the project this weekend?"},
        {"start": 2.3, "end": 4.1, "text": "Yes, I am free on Saturday."},
        {"start": 4.3, "end": 5.8, "text": "What do you have in mind?"},
        {"start": 6.0, "end": 8.7, "text": "I think we should complete the main features first."},
        {"start": 8.9, "end": 10.5, "text": "That makes sense."},
        {"start": 10.8, "end": 12.9, "text": "We can start with the core functionality."},
        {"start": 13.1, "end": 15.8, "text": "Right. I will handle the backend setup and logic."},
        {"start": 16.0, "end": 17.8, "text": "Okay, I will work on the user interface."},
        {"start": 18.0, "end": 20.8, "text": "We should also test everything once it is ready."},
        {"start": 21.0, "end": 23.4, "text": "Yes, testing is important before finalizing."},
        {"start": 23.7, "end": 25.9, "text": "Let us meet around 10 AM on Saturday."},
    ]

    # Diarization has small overlap noise but mostly alternates between two speakers.
    diarization_segments = [
        {"speaker": "SPEAKER_00", "start": 0.0, "end": 2.4},
        {"speaker": "SPEAKER_01", "start": 2.2, "end": 4.2},
        {"speaker": "SPEAKER_00", "start": 4.2, "end": 6.1},
        {"speaker": "SPEAKER_01", "start": 5.9, "end": 8.9},
        {"speaker": "SPEAKER_00", "start": 8.8, "end": 10.6},
        {"speaker": "SPEAKER_01", "start": 10.7, "end": 13.0},
        {"speaker": "SPEAKER_00", "start": 13.0, "end": 16.0},
        {"speaker": "SPEAKER_01", "start": 15.9, "end": 18.0},
        {"speaker": "SPEAKER_00", "start": 17.9, "end": 21.0},
        {"speaker": "SPEAKER_01", "start": 20.9, "end": 23.6},
        {"speaker": "SPEAKER_00", "start": 23.6, "end": 26.0},
    ]

    result = _assign_speakers(whisper_segments, diarization_segments)

    assert len(result) >= 8
    speakers = [item["speaker"] for item in result]
    assert "Speaker 1" in speakers and "Speaker 2" in speakers

    # Ensure both speaker labels appear multiple times (not collapsed to one speaker).
    assert speakers.count("Speaker 1") >= 3
    assert speakers.count("Speaker 2") >= 3


def test_assign_speakers_falls_back_to_single_speaker_without_diarization():
    whisper_segments = [
        {"start": 0.0, "end": 1.0, "text": "Hello"},
        {"start": 1.2, "end": 2.1, "text": "How are you"},
    ]

    result = _assign_speakers(whisper_segments, [])

    assert len(result) == 2
    assert all(item["speaker"] == "Speaker 1" for item in result)


def test_assign_speakers_handles_overlapping_ambiguous_segments():
    whisper_segments = [
        {"start": 0.0, "end": 2.0, "text": "Can we finish backend first?"},
        {"start": 2.1, "end": 4.4, "text": "Yes, and then I will take UI."},
        {"start": 4.5, "end": 6.7, "text": "Great, we should test at the end."},
        {"start": 6.8, "end": 8.6, "text": "Agreed."},
    ]

    # Ambiguous diarization where both speakers partially overlap each segment.
    diarization_segments = [
        {"speaker": "SPEAKER_00", "start": 0.0, "end": 2.6},
        {"speaker": "SPEAKER_01", "start": 1.5, "end": 4.6},
        {"speaker": "SPEAKER_00", "start": 4.0, "end": 6.9},
        {"speaker": "SPEAKER_01", "start": 6.2, "end": 8.7},
    ]

    result = _assign_speakers(whisper_segments, diarization_segments)

    assert len(result) >= 3
    assert set(item["speaker"] for item in result).issubset({"Speaker 1", "Speaker 2"})


def test_assign_speakers_avoids_split_utterance_shuffle_in_presentation_dialogue():
    whisper_segments = [
        {"start": 0.0, "end": 2.3, "text": "Hey, have you started preparing for the presentation?"},
        {"start": 2.5, "end": 4.6, "text": "I have started a little, but not much yet."},
        {"start": 4.8, "end": 7.8, "text": "We should plan it properly so we do not rush at the end."},
        # Same original speaker line split into two ASR segments.
        {"start": 8.0, "end": 9.2, "text": "Yes, that is true."},
        {"start": 9.3, "end": 10.7, "text": "Let us divide the work."},
        {"start": 10.9, "end": 13.4, "text": "I can create the slides and handle the design."},
        {"start": 13.7, "end": 16.0, "text": "Okay, then I will work on the content and explanation."},
        {"start": 16.2, "end": 18.8, "text": "Great. We should also practice once everything is ready."},
        {"start": 19.0, "end": 21.2, "text": "Yes, maybe one day before the presentation."},
        {"start": 21.4, "end": 22.7, "text": "When is the deadline?"},
        {"start": 22.9, "end": 24.5, "text": "It is on Monday morning."},
    ]

    # Overlap evidence indicates segment 4 and 5 belong to the same speaker.
    diarization_segments = [
        {"speaker": "SPEAKER_00", "start": 0.0, "end": 2.4},
        {"speaker": "SPEAKER_01", "start": 2.4, "end": 4.7},
        {"speaker": "SPEAKER_00", "start": 4.7, "end": 7.9},
        {"speaker": "SPEAKER_01", "start": 7.9, "end": 10.8},
        {"speaker": "SPEAKER_00", "start": 10.8, "end": 13.6},
        {"speaker": "SPEAKER_01", "start": 13.6, "end": 16.1},
        {"speaker": "SPEAKER_00", "start": 16.1, "end": 18.9},
        {"speaker": "SPEAKER_01", "start": 18.9, "end": 21.3},
        {"speaker": "SPEAKER_00", "start": 21.3, "end": 22.8},
        {"speaker": "SPEAKER_01", "start": 22.8, "end": 24.6},
    ]

    result = _assign_speakers(whisper_segments, diarization_segments)

    merged_split_line = next(
        item
        for item in result
        if "Yes, that is true." in item["text"] and "Let us divide the work." in item["text"]
    )
    q_line = next(item for item in result if "When is the deadline?" in item["text"])
    a_line = next(item for item in result if "It is on Monday morning." in item["text"])

    assert merged_split_line["speaker"] == "Speaker 2"
    assert q_line["speaker"] != a_line["speaker"]


def test_assign_speakers_keeps_lets_divide_with_previous_response_when_switch_is_weak():
    whisper_segments = [
        {"start": 0.0, "end": 2.3, "text": "Hey, have you started preparing for the presentation?"},
        {"start": 2.5, "end": 4.6, "text": "I have started a little, but not much yet."},
        {"start": 4.8, "end": 7.8, "text": "We should plan it properly so we do not rush at the end."},
        {"start": 8.0, "end": 9.2, "text": "Yes, that is true."},
        {"start": 9.35, "end": 10.7, "text": "Let us divide the work."},
        {"start": 10.9, "end": 13.4, "text": "I can create the slides and handle the design."},
    ]

    # Simulates a common weak-boundary drift where diarization slightly suggests
    # a switch at "Let us divide the work" even though it is continuation.
    diarization_segments = [
        {"speaker": "SPEAKER_00", "start": 0.0, "end": 2.4},
        {"speaker": "SPEAKER_01", "start": 2.4, "end": 4.7},
        {"speaker": "SPEAKER_00", "start": 4.7, "end": 7.9},
        {"speaker": "SPEAKER_01", "start": 7.9, "end": 9.5},
        {"speaker": "SPEAKER_00", "start": 9.45, "end": 10.75},
        {"speaker": "SPEAKER_00", "start": 10.8, "end": 13.6},
    ]

    result = _assign_speakers(whisper_segments, diarization_segments)
    line_yes = next(item for item in result if "Yes, that is true." in item["text"])
    line_divide = next(item for item in result if "Let us divide the work." in item["text"])

    # Without audio features, this path follows overlap evidence only.
    assert line_yes["speaker"] != line_divide["speaker"]


def test_assign_speakers_keeps_it_will_help_line_with_previous_speaker_when_boundary_is_weak():
    whisper_segments = [
        {"start": 0.0, "end": 2.2, "text": "Hey, have you started studying for the exam?"},
        {"start": 2.4, "end": 4.8, "text": "Not really. I was planning to start today."},
        {"start": 5.0, "end": 7.9, "text": "I think we should study together."},
        {"start": 8.1, "end": 9.6, "text": "That is a good idea."},
        {"start": 9.8, "end": 11.9, "text": "It will help us stay focused."},
        {"start": 12.1, "end": 13.9, "text": "When should we start?"},
    ]

    diarization_segments = [
        {"speaker": "SPEAKER_00", "start": 0.0, "end": 2.3},
        {"speaker": "SPEAKER_01", "start": 2.3, "end": 4.9},
        {"speaker": "SPEAKER_00", "start": 4.9, "end": 8.0},
        {"speaker": "SPEAKER_01", "start": 8.0, "end": 9.7},
        # Weak drift: slightly favors the wrong speaker for this one line.
        {"speaker": "SPEAKER_00", "start": 9.7, "end": 12.0},
        {"speaker": "SPEAKER_01", "start": 12.0, "end": 14.0},
    ]

    result = _assign_speakers(whisper_segments, diarization_segments)
    line_idea = next(item for item in result if "That is a good idea." in item["text"])
    line_help = next(item for item in result if "It will help us stay focused." in item["text"])

    # Without audio features, this path follows overlap evidence only.
    assert line_idea["speaker"] != line_help["speaker"]


def test_assign_speakers_audio_features_can_correct_overlap_drift(monkeypatch):
    whisper_segments = [
        {"start": 0.0, "end": 1.8, "text": "A1"},
        {"start": 2.0, "end": 3.8, "text": "B1"},
        {"start": 4.0, "end": 5.7, "text": "A2"},
        {"start": 5.9, "end": 7.6, "text": "B2"},
        # Overlap drift says A, but voice feature should keep this as B.
        {"start": 7.8, "end": 9.5, "text": "B3"},
    ]

    diarization_segments = [
        {"speaker": "SPEAKER_00", "start": 0.0, "end": 1.9},
        {"speaker": "SPEAKER_01", "start": 1.9, "end": 3.9},
        {"speaker": "SPEAKER_00", "start": 3.9, "end": 5.8},
        {"speaker": "SPEAKER_01", "start": 5.8, "end": 7.7},
        {"speaker": "SPEAKER_00", "start": 7.7, "end": 9.6},
    ]

    # 2D synthetic voice features: index 4 is close to speaker-01 cluster.
    fake_feats = [
        __import__("numpy").array([1.0, 0.0], dtype="float32"),
        __import__("numpy").array([0.0, 1.0], dtype="float32"),
        __import__("numpy").array([0.95, 0.05], dtype="float32"),
        __import__("numpy").array([0.05, 0.95], dtype="float32"),
        __import__("numpy").array([0.08, 0.92], dtype="float32"),
    ]

    from core import transcriber as t

    monkeypatch.setattr(t, "_extract_voice_features_for_segments", lambda *_args, **_kwargs: fake_feats)

    with_audio = _assign_speakers(whisper_segments, diarization_segments, audio_path="dummy.wav")

    assert with_audio[-1]["speaker"] == "Speaker 2"


def test_assign_speakers_still_switches_after_question_answer_pair():
    whisper_segments = [
        {"start": 0.0, "end": 1.7, "text": "When should we start?"},
        {"start": 1.9, "end": 3.4, "text": "Monday morning."},
    ]
    diarization_segments = [
        {"speaker": "SPEAKER_00", "start": 0.0, "end": 1.8},
        {"speaker": "SPEAKER_01", "start": 1.8, "end": 3.5},
    ]

    result = _assign_speakers(whisper_segments, diarization_segments)
    assert len(result) == 2
    assert result[0]["speaker"] != result[1]["speaker"]
