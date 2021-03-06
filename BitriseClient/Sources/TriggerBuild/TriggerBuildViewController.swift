import RxCocoa
import RxSwift
import SafariServices
import TKKeyboardControl
import UIKit

/// Scene to trigger a new build on Bitrise CI.
///
/// [Autolayout NOTE]
///
///   - DO NOT make a constraint to safe-area layout guide.
///     Manual frame manipulation with PullToDismiss would cause safe-area
///     to disappear during pan gesture.
///
///   - `rootStackView`'s top (when vertical) and leading (when horizontal)
///     is tied to superview plus 44.
///     This way elements are not covered with iPhoneX*'s bezel.
///     iPhone with no-bezel will sacrifice its screen space a bit,
///     but not a big issue.
///
final class TriggerBuildViewController: UIViewController {

    private let disposeBag = DisposeBag()
    private var viewModel: TriggerBuildViewModel!

    private weak var lastFirstResponder: UIResponder?

    @IBOutlet private weak var rootStackView: UIStackView!

    @IBOutlet private weak var firstStackView: UIStackView!

    @IBOutlet private weak var triggerButton: UIButton! {
        didSet {
            triggerButton.layer.cornerRadius = 5
            triggerButton.layer.borderWidth = 0.7
            triggerButton.layer.borderColor = UIColor.baseGreen.cgColor
        }
    }

    @IBOutlet private weak var gitObjectInputView: GitObjectInputView! {
        didSet {
            gitObjectInputView.layer.zPosition = 1.0

            gitObjectInputView.textFieldDelegate.didBeginEditing
                .subscribe(onNext: { [weak self] _ in
                    self?.reloadSuggestions()
                })
                .disposed(by: disposeBag)

            gitObjectInputView.textFieldDelegate.didEndEditing
                .subscribe(onNext: { [weak self] _ in
                    self?.suggestionTableView.isHidden = true
                })
                .disposed(by: disposeBag)

        }
    }

    private lazy var suggestionTableView: SuggestionTableView = {

        let tableView = SuggestionTableView(suggestions: []) { [weak self] suggestion in
            guard let me = self else { return }

            let currentGitObject = me.gitObjectInputView.newInput.value

            let newGitObject = GitObject(type: currentGitObject.type, name: suggestion)!

            me.gitObjectInputView.updateUI(newGitObject, relay: true)

            me.reloadSuggestions()
        }

        firstStackView.addArrangedSubview(tableView)

        return tableView

    }()

    @IBOutlet private weak var apiTokenTextfield: UITextField! {
        didSet {
            apiTokenTextfield.rx.text
                .filterNil()
                .filterEmpty()
                .subscribe(onNext: { [weak self] apiToken in
                    self?.viewModel?.apiToken = apiToken
                })
                .disposed(by: disposeBag)
        }
    }

    @IBOutlet private weak var tableView: UITableView! {
        didSet {
            tableView.dataSource = self
            tableView.delegate = self
            tableView.allowsMultipleSelectionDuringEditing = false
        }
    }

}

// MARK: LifeCycle

extension TriggerBuildViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // [ActionPopoverButton]
        // Tell rootStackView the hitTest target.
        rootStackView.isUserInteractionEnabled = true
        rootStackView.hth.targetChildToHitTest = gitObjectInputView

        tableView.register(EnvCell.self, forCellReuseIdentifier: "EnvCell")
        tableView.reloadData()

        // No need to perform reactive update for apiTokenTextField.
        // Currently apiToken is not changed outside this view.
        apiTokenTextfield.text = viewModel.apiToken

        gitObjectInputView.newInput.changed
            .subscribe(onNext: { [weak viewModel] gitObject in
                viewModel?.gitObject = gitObject
            })
            .disposed(by: disposeBag)

        gitObjectInputView.updateUI(viewModel.gitObject, relay: false)

        // PullToDismiss
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        gesture.delegate = self
        if let grs = tableView.gestureRecognizers {
            grs.forEach {
                gesture.require(toFail: $0)
            }
        }
        view.addGestureRecognizer(gesture)

        view.keyboardTriggerOffset = 44.0;    // Input view frame height

        view.addKeyboardNonpanning(frameBasedActionHandler: { [weak self] keyboardFrameInView, firstResponder, opening, closing in
            guard let me = self else { return }

            me.lastFirstResponder = firstResponder

            guard let v = firstResponder as? UIView else { return }

            if !closing {
                let keyboardY = keyboardFrameInView.minY

                // NOTE: Set no margins between the keyboard.
                //   to avoid edge case like AddNewCell at bottom on landscape with safeArea.
                //   Modal's presentingVC(BuildListVC) would be visible in background (thru the margin space),
                //   because we are moving self.view frame on keyboard appearance.
                let vMaxY = v.convert(.zero, to: me.view).y + v.frame.height // + 4

                let delta = keyboardY - vMaxY

                if delta < 0 {

                    if v.isDescendant(of: me.gitObjectInputView) {
                        if me.traitCollection.verticalSizeClass == .compact {

                            // FIXME:
                            //   delay workaround for timing issue between suggestionTableView's layout.
                            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
                                me.rootStackView.frame.origin.y = delta - 44
                            }

                        } else {
                            me.rootStackView.frame.origin.y = delta - 44
                        }
                    } else {
                        me.rootStackView.frame.origin.y = delta
                    }

                }

            } else {

                me.rootStackView.frame.origin.y = 0

            }

            if v.isDescendant(of: me.tableView),
                let ip = me.tableView.indexPathForSelectedRow,
                opening {
                me.tableView.deselectRow(at: ip, animated: true)
            }
        })
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        lastFirstResponder?.resignFirstResponder()
    }

    // MARK: Handle PanGesture

    @objc func panGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .ended:
            if gesture.translation(in: view).y > view.frame.height / 2
                || gesture.velocity(in: view).y > 250.0 {
                self.dismiss(animated: true, completion: nil)
            } else {
                view.moveTo(y: 0, animated: true)
            }
        default:
            let translationY = gesture.translation(in: view).y
            if translationY > 0.5 {
                view.moveTo(y: translationY, animated: false)
            }
        }
    }

}

// MARK: UIGestureRecognizerDelegate

extension TriggerBuildViewController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {

        let location = gestureRecognizer.location(in: view)
        let viewsToIgnorePanGesture: [UIView] = [gitObjectInputView]

        for v in viewsToIgnorePanGesture {
            if v.hitTest(view.convert(location, to: v), with: nil) != nil {
                return false
            }
        }

        return true
    }

}

// MARK: IBAction

extension TriggerBuildViewController {

    @IBAction private func triggerButtonTap() {

        Haptic.generate(.light)

        triggerButton.backgroundColor = .baseGreen
        UIView.animate(withDuration: 0.2) { [weak self] in
            self?.triggerButton.backgroundColor = .clear
        }

        gitObjectInputView.resignFirstResponder()
        apiTokenTextfield.resignFirstResponder()

        viewModel.triggerBuild()
    }

    @IBAction private func tokenInfoButton() {
        let url = URL(string: "https://github.com/toshi0383/Bitrise-iOS/blob/master/README.md#build-trigger-token")!
        let vc = SFSafariViewController(url: url)
        self.present(vc, animated: true, completion: nil)
    }

}

// MARK: UITableViewDataSource & UITableViewDelegate

extension TriggerBuildViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return viewModel.workflowIDs.count
        case 1:
            return 1
        case 2:
            return viewModel.environments.count
        case 3:
            return 1
        default:
            fatalError()
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
            cell.textLabel?.text = viewModel.workflowIDs[indexPath.row]
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddNewCell")! as! AnyAddNewCell
            cell.configure(placeholder: "Add new workflowID") { [weak self] text in
                guard let me = self else { return }

                let ip = IndexPath(row: me.viewModel.workflowIDs.count, section: indexPath.section - 1)
                me.viewModel.appendWorkflowID(text)
                me.tableView.insertRows(at: [ip], with: UITableView.RowAnimation.automatic)
                me.tableView.scrollToRow(at: ip, at: .top, animated: true)
            }
            return cell

        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "EnvCell")! as! EnvCell
            let env = viewModel.environments[indexPath.row]
            cell.configure(env) { [weak self] newEnv in
                guard let me = self else { return }

                me.viewModel.setEnvironment(newEnv)
            }
            return cell

        case 3:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddNewCell")! as! AnyAddNewCell
            cell.configure(placeholder: "environment e.g. PLATFORM:tvOS") { [weak self] text in
                guard let me = self else { return }

                let splitted = text.split(separator: ":").map(String.init)
                if splitted.count != 2 {
                    return
                }

                let ip = IndexPath(row: me.viewModel.environments.count, section: indexPath.section - 1)
                me.viewModel.appendEnvironment((splitted[0], splitted[1]))
                me.tableView.insertRows(at: [ip], with: UITableView.RowAnimation.automatic)
                me.tableView.scrollToRow(at: ip, at: .top, animated: true)
            }
            return cell
        default:
            fatalError()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 else { return }

        viewModel.workflowID = viewModel.workflowIDs[indexPath.row]

        lastFirstResponder?.resignFirstResponder()
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section % 2 == 0
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle != .delete {
            return
        }
        switch indexPath.section {
        case 0:
            viewModel.removeWorkflowID(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        case 2:
            viewModel.removeEnvironment(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        default:
            break
        }
    }
}

// MARK: Utilities

extension TriggerBuildViewController {

    private func reloadSuggestions() {

        let currentGitObject = gitObjectInputView.newInput.value

        let suggestions = viewModel
            .getSuggestions(forType: currentGitObject.type)
            .filter { $0 != currentGitObject.name }

        suggestionTableView.isHidden = suggestions.isEmpty

        if !suggestions.isEmpty {
            suggestionTableView.reloadSuggestions(suggestions)
        }
    }

}

// MARK: Storyboardable

extension TriggerBuildViewController: Storyboardable {

    typealias Dependency = TriggerBuildViewModel

    static func makeFromStoryboard(_ viewModel: TriggerBuildViewModel) -> TriggerBuildViewController {
        let vc = TriggerBuildViewController.unsafeMakeFromStoryboard()
        vc.viewModel = viewModel
        return vc
    }

}
