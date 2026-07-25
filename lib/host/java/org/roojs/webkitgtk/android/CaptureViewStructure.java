package org.roojs.webkitgtk.android;

import android.graphics.Matrix;
import android.os.Bundle;
import android.os.LocaleList;
import android.util.Pair;
import android.view.ViewStructure;
import android.view.autofill.AutofillId;
import android.view.autofill.AutofillValue;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * In-process {@link ViewStructure} sink for
 * {@link android.webkit.WebView#onProvideVirtualStructure}.
 *
 * Chromium fills {@link HtmlInfo} (tag + HTML attrs including {@code name} /
 * {@code id}) on this path — the AssistStructure / password-manager side door,
 * parallel to Windows IAccessible2 {@code html-input-name}.
 */
final class CaptureViewStructure extends ViewStructure {
	final List<CaptureViewStructure> children = new ArrayList<>();
	HtmlInfo htmlInfo;
	CharSequence text;
	CharSequence hint;
	String className;
	AutofillId autofillId;
	/** From {@link #setId} entryName when Chromium exposes HTML id this way. */
	String idEntryName = "";
	/** Virtual view id from {@link #setAutofillId(AutofillId, int)}; -1 if unset. */
	int autofillVirtualId = -1;
	int left;
	int top;
	int width;
	int height;
	private Bundle extras;
	private int textSelStart = -1;
	private int textSelEnd = -1;
	/** Fired when Chromium finishes the AssistStructure snapshot. */
	Runnable onAsyncCommit;
	/** Assigned to the next {@link #asyncNewChild} result. */
	Runnable pendingChildCommit;

	static final class CapHtmlInfo extends HtmlInfo {
		private final String tag;
		private final List<Pair<String, String>> attrs;

		CapHtmlInfo(String tag, List<Pair<String, String>> attrs) {
			this.tag = tag != null ? tag : "";
			this.attrs = attrs != null ? attrs : Collections.<Pair<String, String>>emptyList();
		}

		@Override
		public String getTag() {
			return tag;
		}

		@Override
		public List<Pair<String, String>> getAttributes() {
			return attrs;
		}
	}

	static final class CapHtmlInfoBuilder extends HtmlInfo.Builder {
		private final String tag;
		private final List<Pair<String, String>> attrs = new ArrayList<>();

		CapHtmlInfoBuilder(String tag) {
			this.tag = tag;
		}

		@Override
		public HtmlInfo.Builder addAttribute(String name, String value) {
			attrs.add(Pair.create(name, value));
			return this;
		}

		@Override
		public HtmlInfo build() {
			return new CapHtmlInfo(tag, new ArrayList<>(attrs));
		}
	}

	/** Flatten tree depth-first. */
	void flatten(List<CaptureViewStructure> out) {
		out.add(this);
		for (CaptureViewStructure c : children) {
			if (c != null) {
				c.flatten(out);
			}
		}
	}

	String htmlAttr(String key) {
		if (htmlInfo == null || key == null) {
			return "";
		}
		List<Pair<String, String>> attrs = htmlInfo.getAttributes();
		if (attrs == null) {
			return "";
		}
		for (Pair<String, String> p : attrs) {
			if (p != null && key.equals(p.first) && p.second != null) {
				return p.second;
			}
		}
		return "";
	}

	String htmlTag() {
		return htmlInfo != null && htmlInfo.getTag() != null ? htmlInfo.getTag() : "";
	}

	@Override
	public void setId(int id, String packageName, String typeName, String entryName) {
		if (entryName != null) {
			this.idEntryName = entryName;
		}
	}

	@Override
	public void setDimens(int left, int top, int scrollX, int scrollY, int width, int height) {
		this.left = left;
		this.top = top;
		this.width = width;
		this.height = height;
	}

	@Override
	public void setTransformation(Matrix matrix) {
	}

	@Override
	public void setElevation(float elevation) {
	}

	@Override
	public void setAlpha(float alpha) {
	}

	@Override
	public void setVisibility(int visibility) {
	}

	@Override
	public void setEnabled(boolean state) {
	}

	@Override
	public void setClickable(boolean state) {
	}

	@Override
	public void setLongClickable(boolean state) {
	}

	@Override
	public void setContextClickable(boolean state) {
	}

	@Override
	public void setFocusable(boolean state) {
	}

	@Override
	public void setFocused(boolean state) {
	}

	@Override
	public void setAccessibilityFocused(boolean state) {
	}

	@Override
	public void setCheckable(boolean state) {
	}

	@Override
	public void setChecked(boolean state) {
	}

	@Override
	public void setSelected(boolean state) {
	}

	@Override
	public void setActivated(boolean state) {
	}

	@Override
	public void setOpaque(boolean opaque) {
	}

	@Override
	public void setClassName(String className) {
		this.className = className;
	}

	@Override
	public void setContentDescription(CharSequence contentDescription) {
	}

	@Override
	public void setText(CharSequence text) {
		this.text = text;
	}

	@Override
	public void setText(CharSequence text, int selectionStart, int selectionEnd) {
		this.text = text;
		this.textSelStart = selectionStart;
		this.textSelEnd = selectionEnd;
	}

	@Override
	public void setTextStyle(float size, int fgColor, int bgColor, int style) {
	}

	@Override
	public void setTextLines(int[] charOffsets, int[] baselines) {
	}

	@Override
	public void setHint(CharSequence hint) {
		this.hint = hint;
	}

	@Override
	public CharSequence getText() {
		return text;
	}

	@Override
	public int getTextSelectionStart() {
		return textSelStart;
	}

	@Override
	public int getTextSelectionEnd() {
		return textSelEnd;
	}

	@Override
	public CharSequence getHint() {
		return hint;
	}

	@Override
	public Bundle getExtras() {
		if (extras == null) {
			extras = new Bundle();
		}
		return extras;
	}

	@Override
	public boolean hasExtras() {
		return extras != null && !extras.isEmpty();
	}

	@Override
	public void setChildCount(int num) {
		children.clear();
		for (int i = 0; i < num; i++) {
			children.add(null);
		}
	}

	@Override
	public int addChildCount(int num) {
		int start = children.size();
		for (int i = 0; i < num; i++) {
			children.add(null);
		}
		return start;
	}

	@Override
	public int getChildCount() {
		return children.size();
	}

	@Override
	public ViewStructure newChild(int index) {
		ensureChildSlot(index);
		CaptureViewStructure child = new CaptureViewStructure();
		children.set(index, child);
		return child;
	}

	@Override
	public ViewStructure asyncNewChild(int index) {
		CaptureViewStructure child = (CaptureViewStructure) newChild(index);
		if (pendingChildCommit != null) {
			child.onAsyncCommit = pendingChildCommit;
			pendingChildCommit = null;
		}
		return child;
	}

	private void ensureChildSlot(int index) {
		while (children.size() <= index) {
			children.add(null);
		}
	}

	@Override
	public AutofillId getAutofillId() {
		return autofillId;
	}

	@Override
	public void setAutofillId(AutofillId id) {
		this.autofillId = id;
		if (id != null && id.isVirtual()) {
			this.autofillVirtualId = id.getAutofillVirtualId();
		}
	}

	@Override
	public void setAutofillId(AutofillId parentId, int virtualId) {
		this.autofillId = parentId;
		this.autofillVirtualId = virtualId;
	}

	@Override
	public void setAutofillType(int type) {
	}

	@Override
	public void setAutofillHints(String[] autofillHints) {
	}

	@Override
	public void setAutofillValue(AutofillValue value) {
	}

	@Override
	public void setAutofillOptions(CharSequence[] options) {
	}

	@Override
	public void setInputType(int inputType) {
	}

	@Override
	public void setDataIsSensitive(boolean sensitive) {
	}

	@Override
	public void asyncCommit() {
		if (onAsyncCommit != null) {
			Runnable r = onAsyncCommit;
			onAsyncCommit = null;
			r.run();
		}
	}

	@Override
	public void setWebDomain(String domain) {
	}

	@Override
	public void setLocaleList(LocaleList localeList) {
	}

	@Override
	public HtmlInfo.Builder newHtmlInfoBuilder(String tagName) {
		return new CapHtmlInfoBuilder(tagName);
	}

	@Override
	public void setHtmlInfo(HtmlInfo htmlInfo) {
		this.htmlInfo = htmlInfo;
	}
}
