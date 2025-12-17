from pathlib import Path
import pandas as pd


def load_question_batteries(base_path: str | Path) -> list[dict]:
    base = Path(base_path)
    batteries: list[dict] = []

    if not base.exists():
        print("❌ Battery base path does not exist:", base)
        return batteries

    print("📂 Loading question batteries from:", base.resolve())
    print("📂 Folder contents:", [p.name for p in base.iterdir()])

    for xlsx in sorted(base.glob("*.xlsx")):

        # 🔍 DIAGNOSTIC — ADD THIS BLOCK
        print("\n📄 Found Excel file:", xlsx.name)
        print("🔎 xlsx.stem =", repr(xlsx.stem))
        expected_heading = f"{xlsx.stem}_heading.txt"
        print("🔎 Expecting heading file:", expected_heading)
        print(
            "🔎 Heading exists:",
            (base / expected_heading).exists()
        )
        # 🔍 END DIAGNOSTIC

        df = pd.read_excel(xlsx).dropna(how="all")
        if df.empty:
            continue

        # ------------------
        # Battery heading
        # ------------------
        heading_file = base / f"{xlsx.stem}_heading.txt"
        if heading_file.exists():
            heading = heading_file.read_text(encoding="utf-8").strip()
        else:
            heading = xlsx.stem.replace("_", " ").title()

        # ------------------
        # Scale
        # ------------------
        required_cols = {"scale_min", "scale_max", "scale_labels"}
        missing = required_cols - set(df.columns)
        if missing:
            raise ValueError(
                f"{xlsx.name} is missing required columns: {', '.join(missing)}"
            )

        scale_min = int(df.iloc[0]["scale_min"])
        scale_max = int(df.iloc[0]["scale_max"])
        scale_values = list(range(scale_min, scale_max + 1))

        raw_labels = str(df.iloc[0]["scale_labels"])
        scale_labels = [lbl.strip() for lbl in raw_labels.split(";")]

        if len(scale_labels) != len(scale_values):
            raise ValueError(
                f"{xlsx.name}: number of scale_labels ({len(scale_labels)}) "
                f"does not match scale length ({len(scale_values)})"
            )

        # ------------------
        # Questions
        # ------------------
        questions = []
        for _, row in df.iterrows():
            questions.append({
                "question_id": str(row["question_id"]),
                "question_text": str(row["question_text"]),
            })

        batteries.append({
            "name": xlsx.stem,
            "heading": heading,
            "scale": {
                "values": scale_values,
                "labels": scale_labels,
            },
            "questions": questions,
        })

    return batteries
