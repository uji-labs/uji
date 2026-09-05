use tui::state::UiState;

pub fn current_provider(state: &UiState) -> Option<&str> {
    state.current_provider()
}

pub fn current_model(state: &UiState) -> Option<&str> {
    state.current_model()
}
