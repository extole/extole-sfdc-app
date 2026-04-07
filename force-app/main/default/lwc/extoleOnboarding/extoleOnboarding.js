import { LightningElement } from 'lwc';

export default class ExtoleOnboarding extends LightningElement {
    handleGoToSettings() {
        this.dispatchEvent(new CustomEvent('onboardingcomplete'));
    }
}
