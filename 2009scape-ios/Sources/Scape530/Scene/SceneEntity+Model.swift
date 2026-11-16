/// A lit `SoftwareModel` is a scene entity: rt4 `SoftwareModel extends Model extends Entity`.
/// `render` is already `Entity.render`; `getMinY` is `SoftwareModel.getMinY` (computes bounds on demand).
extension SoftwareModel: SceneEntity {
	public func getMinY() -> Int {
		ensureBounds()
		return minY
	}
}
