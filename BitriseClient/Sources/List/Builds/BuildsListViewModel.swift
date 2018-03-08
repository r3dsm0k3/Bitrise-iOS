//
//  BuildsListViewModel.swift
//  BitriseClient
//
//  Created by Toshihiro Suzuki on 2018/02/23.
//

import APIKit
import Continuum
import DeepDiff
import Foundation

final class BuildsListViewModel {

    // MARK: Input

    private let appName: String

    // MARK: Output

    let appSlug: String
    let navigationBarTitle: String
    let alertMessage: Constant<String>
    let dataChanges: Constant<[Change<AppsBuilds.Build>]>
    let isNewDataIndicatorHidden: Constant<Bool>
    // let isMoreDataIndicatorHidden: Constant<Bool>

    // MARK: private properties

    private let _alertMessage = Variable<String>(value: "")
    private let _dataChanges = Variable<[Change<AppsBuilds.Build>]>(value: [])
    private(set) var builds: [AppsBuilds.Build] = []
    let _isNewDataIndicatorHidden = Variable<Bool>(value: true)
    // let isMoreDataIndicatorHidden = Variable<Bool>(value: true)

    private let nextTokenNew = Variable<String?>(value: nil)
    private let nextTokenMore = Variable<String?>(value: nil)

    private let session: Session

    // MARK: Initializer

    init(appSlug: String,
         appName: String,
         session: Session = .shared) {
        self.appSlug = appSlug
        self.appName = appName
        self.navigationBarTitle = appName
        self.session = session

        self.alertMessage = Constant(variable: _alertMessage)
        self.dataChanges = Constant(variable: _dataChanges)
        self.isNewDataIndicatorHidden = Constant(variable: _isNewDataIndicatorHidden)
    }

    // MARK: LifeCycle & Update

    func viewDidLoad() {
        // save app-title
        Config.lastAppNameVisited = appName

        fetchDataAndReloadTable()
    }

    // MARK: API Call

    // TODO: paging
    func fetchDataAndReloadTable() {
        let req = AppsBuildsRequest(appSlug: appSlug)

        session.send(req) { [weak self] result in
            guard let me = self else { return }

            switch result {
            case .success(let res):
                let changes = diff(old: me.builds, new: res.data)
                me.builds = res.data
                me._dataChanges.value = changes
                me.nextTokenMore.value = res.paging.next

            case .failure(let error):
                print(error)
            }
        }
    }

    func triggerPullToRefresh() {
        _isNewDataIndicatorHidden.value = false

        let req = AppsBuildsRequest(appSlug: appSlug, limit: 10)

        session.send(req) { [weak self] result in
            guard let me = self else { return }

            me._isNewDataIndicatorHidden.value = true

            switch result {
            case .success(let res):

                var newBuilds: [AppsBuilds.Build] = me.builds
                var reachedCurrent = false

                for (i, new) in res.data.enumerated() {
                    if newBuilds.containsByBuildNumber(new) {
                        reachedCurrent = true
                        break
                    }
                    newBuilds.insert(new, at: i)
                }

                if !reachedCurrent {
                    print("FIXME: there is new data in between")
                }

                me.nextTokenNew.value = !reachedCurrent ? res.paging.next : nil

                let changes = diff(old: me.builds, new: newBuilds)
                me.builds = newBuilds
                me._dataChanges.value = changes

            case .failure(let error):
                print(error)

            }
        }
    }

    func sendAbortRequest(indexPath: IndexPath) {
        let buildSlug = builds[indexPath.row].slug
        let buildNumber = builds[indexPath.row].build_number
        let req = AppsBuildsAbortRequest(appSlug: appSlug, buildSlug: buildSlug)

        session.send(req) { [weak self] result in
            guard let me = self else { return }

            switch result {
            case .success(let res):
                if let msg = res.error_msg {
                    me._alertMessage.value = msg
                } else {
                    me._alertMessage.value = "Aborted: #\(buildNumber)"

                    // FIXME: only reload aborted build
                    me.fetchDataAndReloadTable()
                }
            case .failure(let error):
                me._alertMessage.value = "Abort failed: \(error.localizedDescription)"
            }
        }
    }

}

private extension Array where Element == AppsBuilds.Build {
    func containsByBuildNumber(_ build: Element) -> Bool {
        return self.contains { $0.build_number == build.build_number }
    }
}