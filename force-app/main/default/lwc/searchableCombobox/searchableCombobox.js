import { LightningElement, api, track } from 'lwc';

export default class SearchableCombobox extends LightningElement {
    @api label = '';
    @api placeholder = 'Search...';
    @api fieldLevelHelp;
    @api required = false;
    @api loading = false;
    @api disabled = false;

    @api
    get value() { return this._value; }
    set value(val) {
        if (val === this._value) return;
        this._value = val;
        this._syncDisplayValue();
    }

    @api
    get options() { return this._options; }
    set options(val) {
        this._options = val || [];
        this._optionsVersion++;
        this._syncDisplayValue();
    }

    // Not @track — changes don't directly trigger re-renders
    _options = [];
    _value = '';

    @track _displayValue = '';
    @track _searchTerm = '';
    @track _optionsVersion = 0;
    @track _focusedIndex = -1;
    @track isOpen = false;
    @track _isSearching = false;
    @track _dropdownFlipped = false;
    @track _dropdownStyle = '';

    _boundOutsideClick;

    connectedCallback() {
        this._boundOutsideClick = this._handleOutsideClick.bind(this);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._boundOutsideClick);
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    renderedCallback() {
        // Only sync the input value when the dropdown is closed.
        // When open, the input is uncontrolled — LWC re-renders must never
        // overwrite what the user is typing (e.g. due to _optionsVersion bumps).
        if (!this.isOpen) {
            const input = this.template.querySelector('input');
            if (input) input.value = this._displayValue || '';
        }
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    get isOpenStr() { return this.isOpen ? 'true' : 'false'; }

    get dropdownClass() {
        return this._dropdownFlipped ? 'sc-dropdown sc-dropdown-up' : 'sc-dropdown';
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${this.isOpen ? ' slds-is-open' : ''}${this.disabled ? ' slds-is-disabled' : ''}`;
    }

    get filteredOptions() {
        const _v = this._optionsVersion; // reactive dependency
        const focused = this._focusedIndex;
        const term = (this._searchTerm || '').toLowerCase();
        return (this._options || [])
            .filter(o => !term || o.label.toLowerCase().includes(term))
            .map((o, i) => ({
                ...o,
                isSelected: o.value === this._value,
                itemClass: [
                    'slds-media slds-listbox__option slds-listbox__option_plain slds-media_small',
                    o.value === this._value ? 'slds-is-selected' : '',
                    i === focused ? 'sc-option-focused' : ''
                ].filter(Boolean).join(' ')
            }));
    }

    get hasFilteredOptions() {
        return this.filteredOptions.length > 0;
    }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handleFocus() {
        // Only set searching mode — never reset state here.
        // LWC re-patches onfocus on re-renders so this fires repeatedly while open.
        // Opening logic is in handleInputClick/handleInput only.
        // Seed _searchTerm with current display value so user can backspace from it.
        if (!this._isSearching) {
            this._isSearching = true;
            this._searchTerm = '';
            this._focusedIndex = -1;
        }
    }

    // No handleBlur: blur fires unreliably during LWC re-renders and causes
    // spurious close-while-typing. Close is handled by outside click + Escape + selection.

    handleInputClick(event) {
        event.stopPropagation();
        if (!this.isOpen) {
            this._searchTerm = '';
            this._open();
        }
    }

    handleInput(event) {
        this._searchTerm = event.target.value;
        this._focusedIndex = -1;
        if (!this.isOpen) {
            this._open();
        }
        this.dispatchEvent(new CustomEvent('search', { detail: { value: this._searchTerm } }));
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            this._close();
            return;
        }
        if (!this.isOpen) return;
        const opts = this.filteredOptions;

        if (event.key === 'ArrowDown') {
            event.preventDefault();
            this._focusedIndex = Math.min(this._focusedIndex + 1, opts.length - 1);
            this._scrollFocusedIntoView();
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            this._focusedIndex = Math.max(this._focusedIndex - 1, 0);
            this._scrollFocusedIntoView();
        } else if (event.key === 'Enter') {
            event.preventDefault();
            if (this._focusedIndex >= 0 && opts[this._focusedIndex]) {
                this._selectOption(opts[this._focusedIndex].value);
            }
        }
    }

    handleDropdownWheel(event) {
        const el = event.currentTarget;
        const atTop = el.scrollTop === 0 && event.deltaY < 0;
        const atBottom = el.scrollTop + el.clientHeight >= el.scrollHeight && event.deltaY > 0;
        if (atTop || atBottom) {
            event.preventDefault();
        }
        event.stopPropagation();
    }

    handleOptionMouseDown(event) {
        event.preventDefault(); // prevents input blur
        const val = event.currentTarget.dataset.value;
        this._selectOption(val);
    }

    // ─── Internals ────────────────────────────────────────────────────────────

    _open() {
        // Seed the input with the current display value before going live.
        // Must be imperative — template has no value binding when open.
        const input = this.template.querySelector('input');
        if (input) {
            input.value = this._displayValue || '';
            const rect = input.getBoundingClientRect();
            // Sentinel appended to the wrapper (inside the same transform context as the dropdown)
            // so it measures the actual fixed-position origin, not the viewport origin.
            const wrapper = this.template.querySelector('.sc-combobox-wrapper');
            const s = document.createElement('div');
            s.style.cssText = 'position:fixed;top:0;left:0;width:0;height:0;pointer-events:none;visibility:hidden';
            (wrapper || document.body).appendChild(s);
            const o = s.getBoundingClientRect();
            (wrapper || document.body).removeChild(s);
            // Use clientHeight as a more reliable measure of the usable viewport in Salesforce's
            // iframe rendering context, where window.innerHeight may exceed the clipped area.
            const viewportH = document.documentElement.clientHeight || window.innerHeight;
            const spaceBelow = viewportH - rect.bottom - 8;
            const spaceAbove = rect.top - o.top - 8;
            const flip = spaceBelow < 200 && spaceAbove > spaceBelow;
            this._dropdownFlipped = flip;
            const left = rect.left - o.left;
            const width = rect.width;
            const maxH = Math.max(80, Math.min(240, flip ? spaceAbove : spaceBelow));
            let posStyle;
            if (flip) {
                posStyle = `top:auto;bottom:${viewportH - rect.top - o.top + 2}px;left:${left}px;width:${width}px;max-height:${maxH}px`;
            } else {
                posStyle = `top:${rect.bottom - o.top + 2}px;bottom:auto;left:${left}px;width:${width}px;max-height:${maxH}px`;
            }
            this._dropdownStyle = posStyle;
        }
        // Pre-focus the currently selected item (or first item if nothing selected)
        const term = (this._searchTerm || '').toLowerCase();
        const filtered = (this._options || []).filter(o => !term || o.label.toLowerCase().includes(term));
        const selectedIndex = filtered.findIndex(o => o.value === this._value);
        this._focusedIndex = selectedIndex >= 0 ? selectedIndex : (filtered.length > 0 ? 0 : -1);
        this.isOpen = true;
        document.addEventListener('click', this._boundOutsideClick);
        if (this._focusedIndex >= 0) {
            this._scrollFocusedIntoView();
        }
    }

    _close() {
        this._isSearching = false;
        this._searchTerm = '';
        this._focusedIndex = -1;
        this.isOpen = false;
        document.removeEventListener('click', this._boundOutsideClick);
    }

    _selectOption(val) {
        const opt = this._options.find(o => o.value === val);
        if (opt) {
            this._value = val;
            this._displayValue = opt.label;
        }
        this._close();
        this.dispatchEvent(new CustomEvent('change', { detail: { value: val } }));
    }

    _scrollFocusedIntoView() {
        setTimeout(() => {
            const focused = this.template.querySelector('.sc-option-focused');
            if (focused) focused.scrollIntoView({ block: 'nearest' });
        }, 0);
    }

    _syncDisplayValue() {
        const opt = (this._options || []).find(o => o.value === this._value);
        const newDisplay = opt ? opt.label : '';
        if (newDisplay !== this._displayValue) {
            this._displayValue = newDisplay;
        }
    }

    _handleOutsideClick() {
        this._close();
    }
}
